#!/usr/bin/env python3
"""
iOS Simulator Push Notification Sender (Python)

Usage:
    python test_ios_notification.py
    python test_ios_notification.py --message "Hello" --title "Bot"
    python test_ios_notification.py --type proactive --message "Important update"
"""

import subprocess
import json
import argparse
import sys
from pathlib import Path


BUNDLE_ID = "com.botsapp.botsapp"
PROJECT_ROOT = Path(__file__).parent.parent


def get_booted_simulator():
    """Get the currently booted iOS simulator ID."""
    result = subprocess.run(
        ["xcrun", "simctl", "list", "devices"],
        capture_output=True,
        text=True
    )

    for line in result.stdout.split('\n'):
        if 'Booted' in line:
            # Extract UUID from line like: "iPhone 15 Pro (ABC-123-DEF) (Booted)"
            import re
            match = re.search(r'\(([A-F0-9-]+)\)', line)
            if match:
                simulator_id = match.group(1)
                simulator_name = line.split('(')[0].strip()
                return simulator_id, simulator_name

    return None, None


def create_notification_payload(notif_type="message", message="Test", title="BotsApp", **kwargs):
    """Create notification payload based on type."""

    import random

    # Random avatar if not specified
    avatar_num = kwargs.get("avatar_num", random.randint(1, 5))
    avatar_url = kwargs.get("avatar_url", f"http://localhost:8000/uploads/test-avatars/avatar-{avatar_num}.png")

    base_payload = {
        "aps": {
            "alert": {
                "title": title,
                "body": message
            },
            "badge": kwargs.get("badge", 1),
            "sound": kwargs.get("sound", "default"),
            "mutable-content": 1,
        }
    }

    if notif_type == "message":
        base_payload["aps"]["category"] = "CHAT_MESSAGE"
        base_payload["type"] = "message"
        base_payload["chat_id"] = kwargs.get("chat_id", "test-chat-123")
        base_payload["message_id"] = kwargs.get("message_id", "msg-123")
        base_payload["bot_name"] = title
        base_payload["avatar_url"] = avatar_url

    elif notif_type == "proactive":
        base_payload["aps"]["alert"]["subtitle"] = "Proactive Check-in"
        base_payload["aps"]["category"] = "CHAT_MESSAGE"
        base_payload["aps"]["interruption-level"] = "active"
        base_payload["type"] = "proactive"
        base_payload["chat_id"] = kwargs.get("chat_id", "test-chat-123")
        base_payload["bot_name"] = title
        base_payload["avatar_url"] = avatar_url

    elif notif_type == "reminder":
        base_payload["aps"]["alert"]["subtitle"] = "Scheduled Reminder"
        base_payload["aps"]["category"] = "CHAT_MESSAGE"
        base_payload["aps"]["interruption-level"] = "time-sensitive"
        base_payload["type"] = "reminder"
        base_payload["reminder_id"] = kwargs.get("reminder_id", "reminder-123")
        base_payload["bot_name"] = title
        base_payload["avatar_url"] = avatar_url

    return base_payload


def send_notification(simulator_id, payload):
    """Send push notification to iOS Simulator."""
    import tempfile

    # Write payload to temporary file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(payload, f, indent=2)
        temp_file = f.name

    try:
        # Send notification
        result = subprocess.run(
            ["xcrun", "simctl", "push", simulator_id, BUNDLE_ID, temp_file],
            capture_output=True,
            text=True
        )

        # Clean up
        Path(temp_file).unlink()

        if result.returncode == 0:
            return True, "Notification sent successfully"
        else:
            return False, result.stderr

    except Exception as e:
        Path(temp_file).unlink(missing_ok=True)
        return False, str(e)


def main():
    parser = argparse.ArgumentParser(
        description='Send push notifications to iOS Simulator'
    )
    parser.add_argument(
        '--type',
        choices=['message', 'proactive', 'reminder'],
        default='message',
        help='Type of notification'
    )
    parser.add_argument(
        '--message',
        default='Test notification from Python script',
        help='Notification message body'
    )
    parser.add_argument(
        '--title',
        default='BotsApp',
        help='Notification title'
    )
    parser.add_argument(
        '--chat-id',
        help='Chat ID (optional)'
    )
    parser.add_argument(
        '--badge',
        type=int,
        default=1,
        help='Badge count'
    )
    parser.add_argument(
        '--json',
        help='Path to custom JSON payload file'
    )

    args = parser.parse_args()

    print("=" * 60)
    print("  iOS Simulator Push Notification Sender (Python)")
    print("=" * 60)

    # Get booted simulator
    simulator_id, simulator_name = get_booted_simulator()

    if not simulator_id:
        print("❌ Error: No booted iOS Simulator found")
        print("💡 Start simulator: open -a Simulator")
        sys.exit(1)

    print(f"✓ Simulator: {simulator_name}")
    print(f"✓ Simulator ID: {simulator_id}")
    print(f"✓ Bundle ID: {BUNDLE_ID}")
    print()

    # Create or load payload
    if args.json:
        print(f"📄 Loading custom payload: {args.json}")
        with open(args.json, 'r') as f:
            payload = json.load(f)
    else:
        print(f"📧 Creating {args.type.upper()} notification")
        kwargs = {}
        if args.chat_id:
            kwargs['chat_id'] = args.chat_id
        kwargs['badge'] = args.badge

        payload = create_notification_payload(
            notif_type=args.type,
            message=args.message,
            title=args.title,
            **kwargs
        )

    print(f"Title: {args.title}")
    print(f"Message: {args.message}")
    print()

    # Send notification
    success, message = send_notification(simulator_id, payload)

    if success:
        print("✅ Notification sent successfully!")
        print()
        print("Payload preview:")
        print(json.dumps(payload, indent=2))
    else:
        print(f"❌ Failed to send notification: {message}")
        sys.exit(1)


if __name__ == "__main__":
    main()
