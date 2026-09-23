package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

var (
	platformServices = []string{
		"alertmanager", "blackbox_exporter", "grafana", "loki", "node_exporter",
		"otel-collector", "prometheus", "pyroscope", "tempo",
	}
	expectedPrometheusJobs = []string{
		"home-monitoring/alertmanager", "home-monitoring/blackbox_exporter",
		"home-monitoring/grafana", "home-monitoring/loki", "home-monitoring/node_exporter",
		"home-monitoring/otel-collector", "home-monitoring/prometheus",
		"home-monitoring/pyroscope", "home-monitoring/tempo",
	}
	expectedTraceServices = []string{"alertmanager", "grafana", "otel-collector", "prometheus"}
	expectedLogServices   = []string{
		"alertmanager", "blackbox_exporter", "grafana", "loki", "node_exporter",
		"otel-collector", "prometheus", "pyroscope", "tempo",
	}
	quietCILogServices = map[string]bool{
		"blackbox_exporter": true,
		"node_exporter":     true,
		"prometheus":        true,
	}
	expectedProfileReceivers = []string{
		"pprof/alertmanager", "pprof/blackbox_exporter", "pprof/grafana", "pprof/loki",
		"pprof/node_exporter", "pprof/otel-collector", "pprof/prometheus",
		"pprof/pyroscope", "pprof/tempo",
	}
)

type config struct {
	compose             []string
	startStack          bool
	timeout             time.Duration
	grafanaURL          string
	grafanaUser         string
	grafanaPassword     string
	grafanaPasswordFile string
	prometheusURL       string
	alertmanagerURL     string
	lokiURL             string
	tempoURL            string
	pyroscopeURL        string
	ci                  bool
}

type verifier struct {
	cfg    config
	client *http.Client
}

type queryResponse struct {
	Status string `json:"status"`
	Data   struct {
		Result []sample `json:"result"`
	} `json:"data"`
}

type sample struct {
	Metric map[string]string `json:"metric"`
	Value  []json.RawMessage `json:"value"`
}

func main() {
	cfg, err := parseConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "[fail] %v\n", err)
		os.Exit(2)
	}

	v := &verifier{cfg: cfg, client: &http.Client{Timeout: 15 * time.Second}}
	if err := v.run(); err != nil {
		fmt.Fprintf(os.Stderr, "[fail] %v\n", err)
		v.printFailureDiagnostics()
		os.Exit(1)
	}
	fmt.Println("[pass] local stack verification completed")
}

func parseConfig() (config, error) {
	startStack := flag.Bool("start", true, "start the platform services before verification")
	noStart := flag.Bool("no-start", false, "do not start the platform services before verification")
	timeoutSeconds := flag.Int("timeout", envInt("TIMEOUT_SECONDS", 180), "timeout in seconds for each readiness or telemetry check")
	flag.Parse()
	if *timeoutSeconds <= 0 {
		return config{}, errors.New("--timeout must be greater than zero")
	}

	compose := strings.Fields(env("COMPOSE", "docker compose -f docker-compose.yml -f docker-compose.platform.yml"))
	if len(compose) == 0 {
		return config{}, errors.New("COMPOSE must not be empty")
	}
	if _, err := exec.LookPath(compose[0]); err != nil {
		return config{}, fmt.Errorf("missing required command %q: %w", compose[0], err)
	}

	return config{
		compose:             compose,
		startStack:          *startStack && !*noStart,
		timeout:             time.Duration(*timeoutSeconds) * time.Second,
		grafanaURL:          env("GRAFANA_URL", "http://localhost:82"),
		grafanaUser:         env("GRAFANA_USER", "admin"),
		grafanaPassword:     os.Getenv("GRAFANA_PASSWORD"),
		grafanaPasswordFile: env("GRAFANA_PASSWORD_FILE", "secrets/grafana-admin-password"),
		prometheusURL:       env("PROMETHEUS_URL", "http://localhost:81"),
		alertmanagerURL:     env("ALERTMANAGER_URL", "http://localhost:83"),
		lokiURL:             env("LOKI_URL", "http://localhost:3100"),
		tempoURL:            env("TEMPO_URL", "http://localhost:3200"),
		pyroscopeURL:        env("PYROSCOPE_URL", "http://localhost:4040"),
		ci:                  os.Getenv("CI") == "true",
	}, nil
}

func (v *verifier) run() error {
	if v.cfg.grafanaPassword == "" {
		password, err := os.ReadFile(v.cfg.grafanaPasswordFile)
		if err != nil {
			return fmt.Errorf("read Grafana password file %s: %w", v.cfg.grafanaPasswordFile, err)
		}
		v.cfg.grafanaPassword = strings.TrimSpace(string(password))
	}

	if err := v.runCompose("config", "--quiet"); err != nil {
		return err
	}
	if v.cfg.startStack {
		if err := os.MkdirAll(filepath.Join("grafana", "storage"), 0o777); err != nil {
			return fmt.Errorf("prepare Grafana storage: %w", err)
		}
		if err := os.Chmod(filepath.Join("grafana", "storage"), 0o777); err != nil {
			return fmt.Errorf("set Grafana storage permissions: %w", err)
		}
		args := append([]string{"up", "-d"}, platformServices...)
		if err := v.runCompose(args...); err != nil {
			return err
		}
	}

	checks := []struct {
		description string
		check       func() error
	}{
		{"all platform Compose services are running", v.checkRunningServices},
		{"Grafana is ready", func() error { return v.httpReady(v.cfg.grafanaURL + "/api/health") }},
		{"Prometheus is ready", func() error { return v.httpReady(v.cfg.prometheusURL + "/-/ready") }},
		{"Alertmanager is ready", func() error { return v.httpReady(v.cfg.alertmanagerURL + "/-/ready") }},
		{"Loki is ready", func() error { return v.httpReady(v.cfg.lokiURL + "/ready") }},
		{"Tempo is ready", func() error { return v.httpReady(v.cfg.tempoURL + "/ready") }},
		{"Pyroscope is ready", func() error { return v.httpReady(v.cfg.pyroscopeURL + "/ready") }},
	}
	for _, item := range checks {
		if err := v.waitUntil(item.description, item.check); err != nil {
			return err
		}
	}

	v.generateActivity()
	telemetryChecks := []struct {
		description string
		check       func() error
	}{
		{"Prometheus has all expected collector-scraped jobs up", v.prometheusHasExpectedJobs},
		{"Prometheus metrics have App O11y service identity", v.prometheusHasAppO11yIdentity},
		{"Loki has recent stack logs", v.lokiHasRecentLogs},
		{"Loki logs from expected services have App O11y identity", v.lokiHasAppO11yServiceLogs},
		{"Tempo has recent traces", v.tempoHasRecentTraces},
		{"Tempo-derived metrics have App O11y service identity", v.tempoHasAppO11yIdentity},
		{"Tempo produces App O11y span metrics", func() error {
			return v.prometheusAnyPositive(`sum(rate(traces_spanmetrics_calls_total{job=~"home-monitoring/[^/]+",service_namespace="home-monitoring",deployment_environment="homelab",deployment_environment_name="homelab",grafana_host_id="homelab"}[5m]))`)
		}},
		{"Tempo identifies the homelab host", func() error {
			return v.prometheusAnyPositive(`sum(traces_host_info{grafana_host_id="homelab",host_source="grafana.host.id"})`)
		}},
		{"Grafana can query the Prometheus datasource", func() error { return v.grafanaDatasourceHealthy("prometheus") }},
		{"Grafana can query the Loki datasource", func() error { return v.grafanaDatasourceHealthy("loki") }},
		{"Grafana can query the Tempo datasource", func() error { return v.grafanaDatasourceHealthy("tempo") }},
		{"Grafana can query the Pyroscope datasource", func() error { return v.grafanaDatasourceHealthy("pyroscope") }},
		{"collector exports metrics to local Prometheus", func() error {
			return v.prometheusAnyPositive(`sum(rate(otelcol_exporter_sent_metric_points_total{exporter="otlp_http/prometheus"}[5m]))`)
		}},
		{"collector exports logs to local Loki", func() error {
			return v.prometheusAnyPositive(`sum(rate(otelcol_exporter_sent_log_records_total{exporter="otlp_http/loki"}[5m]))`)
		}},
		{"collector has at most one Docker log receiver per container", v.collectorHasSingleLogReceiverPerContainer},
		{"collector exports traces to local Tempo", func() error {
			return v.prometheusAnyPositive(`sum(rate(otelcol_exporter_sent_spans_total{exporter="otlp_http/tempo"}[5m]))`)
		}},
		{"collector exports profiles to local Pyroscope", func() error {
			return v.prometheusAnyPositive(`sum(rate(otelcol_exporter_sent_profile_samples_total{exporter="otlp_http/pyroscope"}[5m]))`)
		}},
		{"collector scrapes profiles from all expected services", v.prometheusHasExpectedProfileReceivers},
		{"Pyroscope contains locally ingested profiles", v.pyroscopeHasProfiles},
	}
	for _, item := range telemetryChecks {
		if err := v.waitUntil(item.description, item.check); err != nil {
			return err
		}
	}
	return nil
}

func (v *verifier) waitUntil(description string, check func() error) error {
	deadline := time.Now().Add(v.cfg.timeout)
	var lastErr error
	for {
		if err := check(); err == nil {
			fmt.Printf("[pass] %s\n", description)
			return nil
		} else {
			lastErr = err
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("%s did not become healthy within %s: %w", description, v.cfg.timeout, lastErr)
		}
		time.Sleep(3 * time.Second)
	}
}

func (v *verifier) runCompose(args ...string) error {
	command := append(append([]string{}, v.cfg.compose...), args...)
	fmt.Printf("[verify] %s\n", strings.Join(command, " "))
	cmd := exec.Command(command[0], command[1:]...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("run %s: %w", strings.Join(command, " "), err)
	}
	return nil
}

func (v *verifier) composeOutput(args ...string) ([]byte, error) {
	command := append(append([]string{}, v.cfg.compose...), args...)
	output, err := exec.Command(command[0], command[1:]...).CombinedOutput()
	if err != nil {
		return output, fmt.Errorf("run %s: %w: %s", strings.Join(command, " "), err, strings.TrimSpace(string(output)))
	}
	return output, nil
}

func (v *verifier) checkRunningServices() error {
	output, err := v.composeOutput("ps", "--status", "running", "--services")
	if err != nil {
		return err
	}
	running := makeSet(strings.Fields(string(output)))
	var missing []string
	for _, service := range platformServices {
		if !running[service] {
			missing = append(missing, service)
		}
	}
	if len(missing) != 0 {
		return fmt.Errorf("missing services %v; running services %v", missing, sortedKeys(running))
	}
	return nil
}

func (v *verifier) httpReady(endpoint string) error {
	response, err := v.client.Get(endpoint)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	io.Copy(io.Discard, response.Body)
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("GET %s returned %s", endpoint, response.Status)
	}
	return nil
}

func (v *verifier) generateActivity() {
	for _, endpoint := range []string{
		v.cfg.grafanaURL + "/api/health", v.cfg.prometheusURL + "/-/ready",
		v.cfg.alertmanagerURL + "/-/ready", v.cfg.lokiURL + "/ready",
		v.cfg.tempoURL + "/ready", v.cfg.pyroscopeURL + "/ready",
	} {
		_ = v.httpReady(endpoint)
	}
}

func (v *verifier) prometheusQuery(query string) (queryResponse, error) {
	endpoint := v.cfg.prometheusURL + "/api/v1/query?" + url.Values{"query": []string{query}}.Encode()
	var payload queryResponse
	if err := v.getJSON(endpoint, &payload, "", ""); err != nil {
		return payload, err
	}
	if payload.Status != "success" {
		return payload, fmt.Errorf("Prometheus query failed: %s", query)
	}
	return payload, nil
}

func (v *verifier) prometheusHasExpectedJobs() error {
	payload, err := v.prometheusQuery("min by (job) (up)")
	if err != nil {
		return err
	}
	values := make(map[string]float64)
	for _, item := range payload.Data.Result {
		value, err := sampleValue(item)
		if err != nil {
			return err
		}
		values[item.Metric["job"]] = value
	}
	var missing, down []string
	for _, job := range expectedPrometheusJobs {
		value, ok := values[job]
		if !ok {
			missing = append(missing, job)
		} else if value < 1 {
			down = append(down, job)
		}
	}
	if len(missing) != 0 || len(down) != 0 {
		return fmt.Errorf("missing jobs %v; down jobs %v; observed jobs %v", missing, down, sortedFloatKeys(values))
	}
	return nil
}

func (v *verifier) prometheusHasAppO11yIdentity() error {
	payload, err := v.prometheusQuery(`target_info{service_namespace="home-monitoring"}`)
	if err != nil {
		return err
	}
	expected := makeSet(expectedPrometheusJobs)
	valid := make(map[string]bool)
	instances := make(map[string]map[string]bool)
	var invalid []map[string]string
	for _, item := range payload.Data.Result {
		labels := item.Metric
		job := labels["job"]
		if !expected[job] {
			continue
		}
		name := labels["service_name"]
		instance := labels["service_instance_id"]
		if name != "" && !strings.Contains(name, "/") && job == "home-monitoring/"+name &&
			instance != "" && labels["service_namespace"] == "home-monitoring" &&
			labels["deployment_environment"] == "homelab" &&
			labels["deployment_environment_name"] == "homelab" && labels["grafana_host_id"] == "homelab" {
			valid[job] = true
			if instances[instance] == nil {
				instances[instance] = make(map[string]bool)
			}
			instances[instance][job] = true
		} else {
			invalid = append(invalid, labels)
		}
	}
	missing := missingKeys(expected, valid)
	duplicates := make(map[string][]string)
	for instance, jobs := range instances {
		if len(jobs) > 1 {
			duplicates[instance] = sortedKeys(jobs)
		}
	}
	if len(missing) != 0 || len(invalid) != 0 || len(duplicates) != 0 {
		return fmt.Errorf("missing jobs %v; invalid identity series %s; duplicate instances %v", missing, compactJSON(invalid, 10), duplicates)
	}
	return nil
}

func (v *verifier) prometheusAnyPositive(query string) error {
	payload, err := v.prometheusQuery(query)
	if err != nil {
		return err
	}
	for _, item := range payload.Data.Result {
		value, err := sampleValue(item)
		if err != nil {
			return err
		}
		if value > 0 {
			return nil
		}
	}
	return fmt.Errorf("no positive series for query %q; observed %s", query, compactJSON(payload.Data.Result, 10))
}

func (v *verifier) collectorHasSingleLogReceiverPerContainer() error {
	payload, err := v.prometheusQuery(`sum by (receiver) (rate(otelcol_receiver_accepted_log_records_total{receiver=~"file_log/docker/receiver_creator.*"}[1m]))`)
	if err != nil {
		return err
	}
	pattern := regexp.MustCompile(`/([0-9a-f]{64})(?::[0-9]+)?$`)
	receivers := make(map[string][]string)
	for _, item := range payload.Data.Result {
		value, err := sampleValue(item)
		if err != nil || value <= 0 {
			continue
		}
		receiver := item.Metric["receiver"]
		match := pattern.FindStringSubmatch(receiver)
		if len(match) == 2 {
			receivers[match[1]] = append(receivers[match[1]], receiver)
		}
	}
	duplicates := make(map[string][]string)
	for container, found := range receivers {
		if len(found) > 1 {
			duplicates[container] = found
		}
	}
	if len(duplicates) != 0 {
		return fmt.Errorf("multiple Docker log receivers ingest the same container: %v", duplicates)
	}
	return nil
}

func (v *verifier) prometheusHasExpectedProfileReceivers() error {
	payload, err := v.prometheusQuery("sum by (receiver) (otelcol_scraper_scraped_profile_records_total)")
	if err != nil {
		return err
	}
	observed := make(map[string]bool)
	for _, item := range payload.Data.Result {
		observed[item.Metric["receiver"]] = true
	}
	missing := missingKeys(makeSet(expectedProfileReceivers), observed)
	if len(missing) != 0 {
		return fmt.Errorf("missing profile receivers %v; observed %v", missing, sortedKeys(observed))
	}
	return nil
}

func (v *verifier) lokiQuery(query string) (queryResponse, error) {
	endpoint := v.cfg.lokiURL + "/loki/api/v1/query?" + url.Values{"query": []string{query}}.Encode()
	var payload queryResponse
	if err := v.getJSON(endpoint, &payload, "", ""); err != nil {
		return payload, err
	}
	if payload.Status != "success" {
		return payload, fmt.Errorf("Loki query failed: %s", query)
	}
	return payload, nil
}

func (v *verifier) lokiHasRecentLogs() error {
	payload, err := v.lokiQuery(`sum(count_over_time({container_name=~".+"}[5m]))`)
	if err != nil {
		return err
	}
	for _, item := range payload.Data.Result {
		value, _ := sampleValue(item)
		if value > 0 {
			return nil
		}
	}
	return errors.New("no recent Loki logs found")
}

func (v *verifier) expectedLokiLogServices() map[string]bool {
	expected := makeSet(expectedLogServices)
	if v.cfg.ci {
		for service := range quietCILogServices {
			delete(expected, service)
		}
	}
	return expected
}

func (v *verifier) lokiHasAppO11yServiceLogs() error {
	query := `sum by (service_name, service_namespace, service_instance_id, deployment_environment, deployment_environment_name, grafana_host_id) (count_over_time({service_namespace="home-monitoring"}[30m]))`
	payload, err := v.lokiQuery(query)
	if err != nil {
		return err
	}
	expected := v.expectedLokiLogServices()
	valid := make(map[string]bool)
	var invalid []map[string]string
	for _, item := range payload.Data.Result {
		value, _ := sampleValue(item)
		labels := item.Metric
		name := labels["service_name"]
		if !expected[name] {
			continue
		}
		if value > 0 && name != "" && !strings.Contains(name, "/") &&
			labels["service_namespace"] == "home-monitoring" && labels["service_instance_id"] != "" &&
			labels["deployment_environment"] == "homelab" &&
			labels["deployment_environment_name"] == "homelab" && labels["grafana_host_id"] == "homelab" {
			valid[name] = true
		} else {
			invalid = append(invalid, labels)
		}
	}
	missing := missingKeys(expected, valid)
	if len(missing) != 0 || len(invalid) != 0 {
		return fmt.Errorf("missing log services %v; invalid identity series %s", missing, compactJSON(invalid, 10))
	}
	return nil
}

func (v *verifier) tempoHasRecentTraces() error {
	now := time.Now().Unix()
	endpoint := fmt.Sprintf("%s/api/search?start=%d&end=%d&limit=10", v.cfg.tempoURL, now-900, now)
	var payload struct {
		Traces []json.RawMessage `json:"traces"`
	}
	if err := v.getJSON(endpoint, &payload, "", ""); err != nil {
		return err
	}
	if len(payload.Traces) == 0 {
		return errors.New("no recent Tempo traces found")
	}
	return nil
}

func (v *verifier) tempoHasAppO11yIdentity() error {
	payload, err := v.prometheusQuery(`traces_target_info{deployment_environment="homelab",deployment_environment_name="homelab",grafana_host_id="homelab"}`)
	if err != nil {
		return err
	}
	expected := makeSet(expectedTraceServices)
	valid := make(map[string]bool)
	instances := make(map[string]string)
	var invalid []map[string]string
	for _, item := range payload.Data.Result {
		labels := item.Metric
		job := labels["job"]
		if !strings.HasPrefix(job, "home-monitoring/") {
			continue
		}
		name := strings.TrimPrefix(job, "home-monitoring/")
		if !expected[name] || strings.Contains(name, "/") {
			continue
		}
		instance := labels["instance"]
		if instance == "" {
			invalid = append(invalid, labels)
			continue
		}
		if prior, ok := instances[instance]; ok && prior != name {
			invalid = append(invalid, labels)
			continue
		}
		instances[instance] = name
		valid[name] = true
	}
	missing := missingKeys(expected, valid)
	if len(missing) != 0 {
		return fmt.Errorf("missing trace services %v; invalid identity series %s", missing, compactJSON(invalid, 10))
	}
	return nil
}

func (v *verifier) pyroscopeHasProfiles() error {
	now := time.Now()
	requestBody, _ := json.Marshal(map[string]any{
		"start": now.Add(-time.Hour).UnixMilli(), "end": now.UnixMilli(),
		"name": "__name__", "matchers": []any{},
	})
	request, err := http.NewRequest(http.MethodPost, v.cfg.pyroscopeURL+"/querier.v1.QuerierService/LabelValues", bytes.NewReader(requestBody))
	if err != nil {
		return err
	}
	request.Header.Set("Content-Type", "application/json")
	var payload struct {
		Names []string `json:"names"`
	}
	if err := v.doJSON(request, &payload); err != nil {
		return err
	}
	if len(payload.Names) == 0 {
		return errors.New("Pyroscope does not contain any profiles")
	}
	return nil
}

func (v *verifier) grafanaDatasourceHealthy(uid string) error {
	endpoint := fmt.Sprintf("%s/api/datasources/uid/%s/health", v.cfg.grafanaURL, url.PathEscape(uid))
	var payload struct {
		Status string `json:"status"`
	}
	if err := v.getJSON(endpoint, &payload, v.cfg.grafanaUser, v.cfg.grafanaPassword); err != nil {
		return err
	}
	if payload.Status != "OK" {
		return fmt.Errorf("Grafana datasource %s health status is %q", uid, payload.Status)
	}
	return nil
}

func (v *verifier) getJSON(endpoint string, target any, username, password string) error {
	request, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	if username != "" {
		request.SetBasicAuth(username, password)
	}
	return v.doJSON(request, target)
}

func (v *verifier) doJSON(request *http.Request, target any) error {
	response, err := v.client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil {
		return err
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("%s %s returned %s: %s", request.Method, request.URL, response.Status, strings.TrimSpace(string(body)))
	}
	if err := json.Unmarshal(body, target); err != nil {
		return fmt.Errorf("decode response from %s: %w", request.URL, err)
	}
	return nil
}

func (v *verifier) printFailureDiagnostics() {
	fmt.Fprintln(os.Stderr, "[diag] failure_diagnostics=begin")
	if output, err := v.composeOutput("ps"); err == nil {
		fmt.Fprintln(os.Stderr, string(output))
	} else {
		fmt.Fprintln(os.Stderr, err)
	}
	for name, query := range map[string]string{
		"prometheus_jobs":          "count by (job) (up)",
		"collector_export_metrics": "sum by (exporter) (rate(otelcol_exporter_sent_metric_points_total[5m]))",
		"collector_export_logs":    "sum by (exporter) (rate(otelcol_exporter_sent_log_records_total[5m]))",
		"collector_export_traces":  "sum by (exporter) (rate(otelcol_exporter_sent_spans_total[5m]))",
	} {
		if payload, err := v.prometheusQuery(query); err == nil {
			fmt.Fprintf(os.Stderr, "[diag] %s=%s\n", name, compactJSON(payload.Data.Result, 20))
		} else {
			fmt.Fprintf(os.Stderr, "[diag] %s_error=%v\n", name, err)
		}
	}
	if output, err := v.composeOutput("logs", "--no-color", "--tail=120", "otel-collector"); err == nil {
		fmt.Fprintf(os.Stderr, "[diag] otel_collector_logs=begin\n%s[diag] otel_collector_logs=end\n", output)
	} else {
		fmt.Fprintf(os.Stderr, "[diag] otel_collector_logs_error=%v\n", err)
	}
	fmt.Fprintln(os.Stderr, "[diag] failure_diagnostics=end")
}

func sampleValue(item sample) (float64, error) {
	if len(item.Value) < 2 {
		return 0, errors.New("query sample has no value")
	}
	var value string
	if err := json.Unmarshal(item.Value[1], &value); err != nil {
		return 0, err
	}
	return strconv.ParseFloat(value, 64)
}

func env(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

func envInt(name string, fallback int) int {
	value := os.Getenv(name)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func makeSet(values []string) map[string]bool {
	result := make(map[string]bool, len(values))
	for _, value := range values {
		result[value] = true
	}
	return result
}

func missingKeys(expected, observed map[string]bool) []string {
	var missing []string
	for item := range expected {
		if !observed[item] {
			missing = append(missing, item)
		}
	}
	sort.Strings(missing)
	return missing
}

func sortedKeys(values map[string]bool) []string {
	result := make([]string, 0, len(values))
	for value := range values {
		result = append(result, value)
	}
	sort.Strings(result)
	return result
}

func sortedFloatKeys(values map[string]float64) []string {
	result := make([]string, 0, len(values))
	for value := range values {
		result = append(result, value)
	}
	sort.Strings(result)
	return result
}

func compactJSON(value any, limit int) string {
	if items, ok := value.([]map[string]string); ok && len(items) > limit {
		value = items[:limit]
	}
	if items, ok := value.([]sample); ok && len(items) > limit {
		value = items[:limit]
	}
	encoded, err := json.Marshal(value)
	if err != nil {
		return fmt.Sprintf("%v", value)
	}
	return string(encoded)
}
