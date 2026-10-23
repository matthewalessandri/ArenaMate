"""Validate release inputs without logging signing material."""
import base64
import binascii
import os
import re


def release_version(tag):
    match = re.fullmatch(r"v?(\d+\.\d+\.\d+)", tag)
    if not match:
        raise ValueError("Release tags must use vMAJOR.MINOR.PATCH (for example v4.6.2).")
    return match[1]


def validate_key(value, lengths, label):
    try:
        decoded = base64.b64decode("".join(value.split()), validate=True)
    except (ValueError, binascii.Error):
        raise ValueError(f"{label} is missing or is not valid base64.") from None
    if len(decoded) not in lengths:
        raise ValueError(f"{label} has an invalid decoded length.")


if __name__ == "__main__":
    try:
        version = release_version(os.environ["RELEASE_TAG"])
        validate_key(os.environ.get("SPARKLE_PUBLIC_ED_KEY", ""), {32}, "SPARKLE_PUBLIC_ED_KEY repository variable")
        validate_key(os.environ.get("SPARKLE_PRIVATE_ED_KEY", ""), {32, 96}, "SPARKLE_PRIVATE_ED_KEY repository secret")
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            output.write(f"version={version}\n")
    except (ValueError, KeyError) as error:
        raise SystemExit(str(error)) from None
