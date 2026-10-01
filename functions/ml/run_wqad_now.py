"""Run the scheduled WQAD analysis once from a local test environment."""

import argparse
import json
from pathlib import Path

import firebase_admin
from firebase_admin import credentials


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Analyze the currently assigned tank now and write its WQAD current "
            "result plus one history result to Firestore."
        )
    )
    parser.add_argument("--credentials", required=True, help="Service-account JSON path")
    parser.add_argument("--project-id", required=True, help="Expected Firebase project ID")
    args = parser.parse_args()

    credential_path = Path(args.credentials).resolve(strict=True)
    service_account = json.loads(credential_path.read_text(encoding="utf-8"))
    credential_project = service_account.get("project_id")
    if credential_project != args.project_id:
        parser.error(
            "Service-account project does not match the requested Firebase project; "
            "no analysis was run."
        )

    firebase_admin.initialize_app(
        credentials.Certificate(service_account),
        {"projectId": args.project_id},
    )

    # Reuse the same owner/tank validation, inference, and Firestore writes as
    # the deployed hourly scheduled function.
    from main import run_wqad_now

    run_wqad_now()


if __name__ == "__main__":
    main()
