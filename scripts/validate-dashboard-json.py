#!/usr/bin/env python3

import json
import sys
from pathlib import Path


DEFAULT_DASHBOARD_DIR = Path("grafana/provisioning/dashboards/home")


def fail(errors, path, message):
    errors.append(f"{path}: {message}")


def validate_resource_dashboard(path, dashboard, errors):
    required = ("apiVersion", "kind", "metadata", "spec")
    missing = [key for key in required if key not in dashboard]
    if missing:
        fail(errors, path, f"missing Grafana resource field(s): {', '.join(missing)}")
        return

    if dashboard["apiVersion"] != "dashboard.grafana.app/v2":
        fail(errors, path, "apiVersion must be dashboard.grafana.app/v2")

    if dashboard["kind"] != "Dashboard":
        fail(errors, path, "kind must be Dashboard")

    if not isinstance(dashboard["metadata"], dict):
        fail(errors, path, "metadata must be an object")

    spec = dashboard["spec"]
    if not isinstance(spec, dict):
        fail(errors, path, "spec must be an object")
        return

    for key in ("title", "elements", "layout"):
        if key not in spec:
            fail(errors, path, f"spec missing required dashboard field: {key}")


def validate_classic_dashboard(path, dashboard, errors):
    if "elements" in dashboard and "layout" in dashboard:
        fail(
            errors,
            path,
            "looks like a Grafana v2 dashboard spec, but is missing the apiVersion/kind/metadata/spec resource wrapper",
        )
        return

    if not isinstance(dashboard.get("title"), str) or not dashboard["title"]:
        fail(errors, path, "classic dashboard must have a non-empty title")

    if not isinstance(dashboard.get("panels"), list):
        fail(errors, path, "classic dashboard must have a panels array")


def validate_dashboard(path):
    errors = []

    try:
        dashboard = json.loads(path.read_text())
    except json.JSONDecodeError as err:
        return [f"{path}: invalid JSON: {err}"]

    if not isinstance(dashboard, dict):
        return [f"{path}: dashboard JSON must be an object"]

    if any(key in dashboard for key in ("apiVersion", "kind", "metadata", "spec")):
        validate_resource_dashboard(path, dashboard, errors)
    else:
        validate_classic_dashboard(path, dashboard, errors)

    return errors


def dashboard_paths(args):
    if args:
        paths = [Path(arg) for arg in args]
    else:
        paths = sorted(DEFAULT_DASHBOARD_DIR.glob("*.json"))

    return [path for path in paths if path.is_file()]


def main():
    errors = []
    paths = dashboard_paths(sys.argv[1:])

    if not paths:
        print("No dashboard JSON files found.")
        return 0

    for path in paths:
        errors.extend(validate_dashboard(path))

    if errors:
        print("Dashboard JSON validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"Validated {len(paths)} dashboard JSON file(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
