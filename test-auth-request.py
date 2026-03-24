#!/usr/bin/env python3
"""
Test script simulating a consuming module requesting keycard authorization.

Simulates the OAuth-like flow:
1. Consumer calls requestAuth(domain, caller)
2. User opens keycard-ui and sees pending request
3. User authorizes in keycard-ui
4. Consumer polls checkAuthStatus(authId) until complete
5. Consumer receives derived key

This demonstrates the Module-Managed Auth State pattern.
"""

import json
import time
import sys
from pathlib import Path

# Add logos-app Python bindings if available (we'll use subprocess instead)
import subprocess

def call_module(method: str, args: list) -> dict:
    """Call keycard module via logos.callModule (simulated with direct test)."""
    # For now, we'll document the expected API calls
    # In production, consuming modules would use: logos.callModule("keycard", method, args)
    print(f"📞 logos.callModule('keycard', '{method}', {args})")

    # Simulate API call - in production this would be:
    # result_json = logos.callModule("keycard", method, args)
    # return json.loads(result_json)

    # For testing, we'll show what the response should look like
    if method == "requestAuth":
        return {
            "authId": "test-auth-id-12345",
            "status": "pending",
            "message": "Authorization request created. Open Keycard UI to complete."
        }
    elif method == "checkAuthStatus":
        # Initially pending, then complete
        return {
            "authId": args[0],
            "status": "pending",  # Will change to "complete" after user authorizes
            "domain": "notes-encryption",
            "caller": "notes"
        }

    return {"error": "Not implemented in test script"}


def main():
    print("=== Keycard Authorization Request Test ===\n")
    print("This script simulates a consuming module (e.g., notes) requesting")
    print("keycard authorization for domain-scoped encryption.\n")

    # Step 1: Request authorization
    print("Step 1: Notes module requests authorization")
    domain = "notes-encryption"
    caller = "notes"

    result = call_module("requestAuth", [domain, caller])

    if "error" in result:
        print(f"❌ Error: {result['error']}")
        return 1

    auth_id = result.get("authId")
    print(f"✅ Authorization requested")
    print(f"   Auth ID: {auth_id}")
    print(f"   Status: {result.get('status')}")
    print(f"   Message: {result.get('message')}\n")

    # Step 2: Poll for completion
    print("Step 2: Polling for authorization completion...")
    print("   (User should now open Keycard UI and authorize the request)\n")

    max_attempts = 60  # 60 attempts = 5 minutes at 5 second intervals
    attempt = 0

    while attempt < max_attempts:
        attempt += 1
        time.sleep(5)

        status_result = call_module("checkAuthStatus", [auth_id])
        status = status_result.get("status")

        print(f"   Poll #{attempt}: Status = {status}")

        if status == "complete":
            key = status_result.get("key")
            print(f"\n✅ Authorization complete!")
            print(f"   Derived key: {key[:32]}..." if key else "   (no key in response)")
            return 0
        elif status == "failed":
            error = status_result.get("error")
            print(f"\n❌ Authorization failed: {error}")
            return 1
        elif status == "pending":
            continue
        else:
            print(f"\n⚠️  Unknown status: {status}")
            return 1

    print(f"\n⏱️  Timeout: No authorization after {max_attempts} attempts")
    return 1


if __name__ == "__main__":
    sys.exit(main())
