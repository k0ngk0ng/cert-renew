#!/usr/bin/env python3
import argparse
import mimetypes
import os
import smtplib
import ssl
from email.message import EmailMessage


def str_to_bool(value: str) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", required=True, type=int)
    parser.add_argument("--username", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--from-addr", required=True)
    parser.add_argument("--to-addrs", required=True)
    parser.add_argument("--subject", required=True)
    parser.add_argument("--body", required=True)
    parser.add_argument("--attachment", required=True)
    parser.add_argument("--use-ssl", default="true")
    args = parser.parse_args()

    recipients = [item.strip() for item in args.to_addrs.split(",") if item.strip()]
    if not recipients:
        raise SystemExit("no recipients provided")

    message = EmailMessage()
    message["From"] = args.from_addr
    message["To"] = ", ".join(recipients)
    message["Subject"] = args.subject
    message.set_content(args.body)

    attachment_path = args.attachment
    content_type, _ = mimetypes.guess_type(attachment_path)
    if content_type is None:
      content_type = "application/octet-stream"
    maintype, subtype = content_type.split("/", 1)

    with open(attachment_path, "rb") as handle:
      message.add_attachment(
          handle.read(),
          maintype=maintype,
          subtype=subtype,
          filename=os.path.basename(attachment_path),
      )

    if str_to_bool(args.use_ssl):
      context = ssl.create_default_context()
      with smtplib.SMTP_SSL(args.host, args.port, context=context) as server:
          server.login(args.username, args.password)
          server.send_message(message)
    else:
      with smtplib.SMTP(args.host, args.port) as server:
          server.starttls(context=ssl.create_default_context())
          server.login(args.username, args.password)
          server.send_message(message)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
