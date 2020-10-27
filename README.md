Stupid simple setup to monitor my stuff at home.

Also an opportunity to build some data to work with for my Prometheus contributions, and to experiment different tools.

---

| Tool    | Function   |
|---------------|---------------------------|
| [Prometheus](https://github.com/prometheus/prometheus)    | Metrics data collection   |
| [Grafana](https://github.com/grafana/grafana)       | Data visualization        |
| [Alertmanager](https://github.com/prometheus/alertmanager)  | Alert management          |
| [Telegrambot](https://github.com/metalmatze/alertmanager-bot)   | Alert routing to Telegram |
| [Node-exporter](https://github.com/prometheus/node_exporter) | Notebook metrics exposure |

---

### RoadMap
* Data exploration:
  * I have network problems every day, still couldn't discover where is the problem
  * Sometimes, all my CPU is consumed at once, not sure why... I need to add an proccess exporter to the setup
* Logging and Tracing:
  * I want to play around with Loki and Tempo in a near future
    * Set up Loki
    * Set up Tempo