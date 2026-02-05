# Telegram JSONL Schema

Each line in the output JSONL file is a single message record.

Fields:
- `source`: "telegram" or "whatsapp".
- `chat_id`: Numeric chat id.
- `chat_title`: Chat title at time of sync (if available).
- `chat_username`: Chat username (if available).
- `message_id`: Numeric message id.
- `date`: ISO-8601 timestamp (UTC, as provided by Telethon).
- `sender_id`: Numeric user id (if available).
- `sender_username`: Username (if available).
- `text`: Message text (may be empty).
- `is_service`: Boolean, true for service/system messages.
- `has_media`: Boolean, true if message includes media.
- `reply_to_msg_id`: Message id this message replies to (if any).
- `run_id`: ISO-8601 timestamp when the sync ran.

Example:
{
  "source": "telegram",
  "chat_id": 123456789,
  "chat_title": "Example Group",
  "chat_username": "example_group",
  "message_id": 321,
  "date": "2026-02-04T10:15:32+00:00",
  "sender_id": 1111111,
  "sender_username": "alice",
  "text": "Hello",
  "is_service": false,
  "has_media": false,
  "reply_to_msg_id": null,
  "run_id": "2026-02-04T10:20:00+00:00"
}
