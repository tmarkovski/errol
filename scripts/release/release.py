# /// script
# requires-python = ">=3.11"
# dependencies = ["click>=8.1", "cryptography>=45", "dmgbuild==1.6.7"]
# ///
"""Builds, signs, notarizes, and packages Errol, one step per command.

The release workflow (.github/workflows/release.yml) runs these commands in
order, and so can anyone with the credentials on their own Mac:

    uv run scripts/release/release.py archive --version 1.0.0 --build 812 --out build
    uv run scripts/release/release.py notarize build/Errol.app
    uv run scripts/release/release.py zip build/Errol.app dist/Errol-1.0.0.zip
    uv run scripts/release/release.py dmg build/Errol.app dist/Errol-1.0.0.dmg --sign
    uv run scripts/release/release.py notarize dist/Errol-1.0.0.dmg
    uv run scripts/release/release.py appcast dist/Errol-1.0.0.zip --tag v1.0.0 --out dist

`archive --signing development` or `--signing adhoc` builds without the
Developer ID certificate, for trying the packaging steps before it exists, and
`rehearse` turns two development builds into an update that can be tried on
this Mac with no credentials at all.

Credentials come from the environment in CI and from the keychain on a Mac:
notarizing reads NOTARY_KEY_P8 (base64), NOTARY_KEY_ID, and NOTARY_ISSUER_ID
when they're set, and otherwise the `errol-notary` profile that
`xcrun notarytool store-credentials` saves. The appcast is signed with the
Sparkle key from the keychain, or from standard input with `--key-file -`.
"""

import base64
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

import click
import dmgbuild
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

HERE = Path(__file__).parent
REPO = HERE.parent.parent
PROJECT = REPO / "app/Errol/Errol.xcodeproj"
RELEASE_XCCONFIG = REPO / "Config/Release.xcconfig"
SCHEME = "Errol"
APP_NAME = "Errol"
TEAM_ID = "JN3SN725AZ"
GITHUB_REPO = "tmarkovski/errol"
WEBSITE = "https://errol.chat"

# The tools that sign updates and write the appcast come from Sparkle's own
# release, the same version the app links. The checksum was taken when the
# version was pinned; change both together, along with the package version in
# the Xcode project, which `appcast` checks against this one.
SPARKLE_VERSION = "2.9.6"
SPARKLE_SHA256 = "52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"

# Where the two icons sit in the disk image's window, as points from its top
# left corner. They have to match the path drawn in dmg/background.html.
DMG_APP_AT = (170, 176)
DMG_APPLICATIONS_AT = (470, 176)


def run(*args: str | Path, check: bool = True, **kwargs) -> subprocess.CompletedProcess:
    """Runs a command, echoing it, and stops the release if it fails."""
    click.secho("$ " + " ".join(str(a) for a in args), fg="bright_black", err=True)
    result = subprocess.run([str(a) for a in args], **kwargs)
    if check and result.returncode != 0:
        for captured in (result.stdout, result.stderr):
            if captured:
                click.echo(captured if isinstance(captured, str) else captured.decode(errors="replace"), err=True)
        raise click.ClickException(f"{Path(str(args[0])).name} exited with {result.returncode}")
    return result


@click.group()
def cli() -> None:
    """Build, sign, notarize, and package Errol."""


# --- archive -----------------------------------------------------------------


def release_settings() -> list[str]:
    """The distribution signing settings, as KEY=VALUE arguments for xcodebuild.

    The target sets its signing in project.pbxproj, and target settings beat a
    base configuration file, so Config/Release.xcconfig isn't attached to the
    project. Settings on the command line beat both.
    """
    settings = []
    for line in RELEASE_XCCONFIG.read_text().splitlines():
        match = re.match(r"^([A-Z_]+)\s*=\s*(.*?)\s*$", line)
        if match:
            settings.append(f"{match[1]}={match[2]}")
    return settings


@cli.command()
@click.option("--version", "marketing", required=True, help="The version people see, like 1.0.0.")
@click.option("--build", "build", required=True, type=click.IntRange(min=1), help="The build number Sparkle compares.")
@click.option(
    "--signing",
    type=click.Choice(["developer-id", "development", "adhoc"]),
    default="developer-id",
    show_default=True,
    help="developer-id for a release; development signs with your Apple Development certificate; "
    "adhoc signs with no certificate at all, as a CI runner without the secrets can.",
)
@click.option("--out", type=click.Path(file_okay=False, path_type=Path), required=True, help="Where Errol.app goes.")
def archive(marketing: str, build: int, signing: str, out: Path) -> None:
    """Archive the app and export Errol.app into OUT."""
    out.mkdir(parents=True, exist_ok=True)
    archive_path = out / f"{APP_NAME}.xcarchive"
    shutil.rmtree(archive_path, ignore_errors=True)
    settings = [f"MARKETING_VERSION={marketing}", f"CURRENT_PROJECT_VERSION={build}"]
    if signing == "developer-id":
        settings += release_settings()
    elif signing == "adhoc":
        settings += ["CODE_SIGN_IDENTITY=-", "CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM="]
    run(
        "xcodebuild", "archive", "-quiet",
        "-project", PROJECT,
        "-scheme", SCHEME,
        "-configuration", "Release",
        "-destination", "generic/platform=macOS",
        "-archivePath", archive_path,
        *settings,
    )  # fmt: skip

    app = out / f"{APP_NAME}.app"
    shutil.rmtree(app, ignore_errors=True)
    if signing == "developer-id":
        # Export re-signs everything inside the app, Sparkle's helpers too,
        # with the Developer ID certificate and a secure timestamp.
        export = out / "export"
        shutil.rmtree(export, ignore_errors=True)
        options = out / "ExportOptions.plist"
        options.write_bytes(
            plistlib.dumps(
                {"method": "developer-id", "signingStyle": "manual", "teamID": TEAM_ID, "destination": "export"}
            )
        )
        run(
            "xcodebuild", "-exportArchive", "-quiet",
            "-archivePath", archive_path,
            "-exportOptionsPlist", options,
            "-exportPath", export,
        )  # fmt: skip
        (export / f"{APP_NAME}.app").rename(app)
        shutil.rmtree(export)
    else:
        run("ditto", archive_path / f"Products/Applications/{APP_NAME}.app", app)

    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    click.echo(f"wrote {app} ({info['CFBundleShortVersionString']}, build {info['CFBundleVersion']}, {signing})")


# --- notarize ----------------------------------------------------------------


def notary_credentials(profile: str, scratch: Path) -> list[str]:
    """The arguments that tell notarytool who is asking."""
    key = os.environ.get("NOTARY_KEY_P8")
    if key:
        key_id = os.environ.get("NOTARY_KEY_ID")
        issuer = os.environ.get("NOTARY_ISSUER_ID")
        if not key_id or not issuer:
            raise click.ClickException("NOTARY_KEY_P8 is set, but NOTARY_KEY_ID or NOTARY_ISSUER_ID is missing")
        path = scratch / "notary.p8"
        path.write_bytes(base64.b64decode(key))
        path.chmod(0o600)
        return ["--key", str(path), "--key-id", key_id, "--issuer", issuer]
    return ["--keychain-profile", profile]


@cli.command()
@click.argument("path", type=click.Path(exists=True, path_type=Path))
@click.option(
    "--keychain-profile",
    default="errol-notary",
    show_default=True,
    help="The notarytool profile to use when NOTARY_KEY_P8 isn't set.",
)
def notarize(path: Path, keychain_profile: str) -> None:
    """Notarize an app or a disk image and staple the ticket to it.

    An app goes up as a ZIP, since notarytool won't take a bundle, and the
    ticket is stapled to the app itself. That's why the ZIP for Sparkle is made
    afterwards: a ZIP can't carry a ticket, only an app inside it can.
    """
    if path.suffix not in (".app", ".dmg"):
        raise click.BadParameter("expected an .app or a .dmg", param_hint="PATH")
    with tempfile.TemporaryDirectory() as scratch_dir:
        scratch = Path(scratch_dir)
        upload = path
        if path.suffix == ".app":
            upload = scratch / f"{path.stem}.zip"
            run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", path, upload)
        credentials = notary_credentials(keychain_profile, scratch)
        # Not checked: a rejected submission exits nonzero, and its log is
        # what's worth seeing.
        result = run(
            "xcrun", "notarytool", "submit", upload, *credentials,
            "--wait", "--timeout", "30m", "--output-format", "json",
            check=False, capture_output=True, text=True,
        )  # fmt: skip
        try:
            submission = json.loads(result.stdout)
        except json.JSONDecodeError:
            click.echo(result.stdout + result.stderr, err=True)
            raise click.ClickException("notarytool didn't say what happened to the submission") from None
        click.echo(f"notarization {submission.get('id')}: {submission.get('status')}")
        if submission.get("status") != "Accepted":
            # The log says which file failed and why.
            if submission.get("id"):
                run("xcrun", "notarytool", "log", submission["id"], *credentials, check=False)
            raise click.ClickException(f"Apple did not accept {path.name}")
    run("xcrun", "stapler", "staple", path)
    run("xcrun", "stapler", "validate", path)


# --- zip and dmg ---------------------------------------------------------------


@cli.command("zip")
@click.argument("app", type=click.Path(exists=True, file_okay=False, path_type=Path))
@click.argument("output", type=click.Path(dir_okay=False, path_type=Path))
def zip_app(app: Path, output: Path) -> None:
    """Pack APP into the ZIP that Sparkle downloads."""
    output.parent.mkdir(parents=True, exist_ok=True)
    output.unlink(missing_ok=True)
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, output)
    click.echo(f"wrote {output}")


def developer_id_identity() -> str:
    """The SHA-1 of the one Developer ID Application identity for the team."""
    listing = run("security", "find-identity", "-v", "-p", "codesigning", capture_output=True, text=True).stdout
    matches = [
        line.split()[1]
        for line in listing.splitlines()
        if '"Developer ID Application:' in line and f"({TEAM_ID})" in line
    ]
    if len(matches) != 1:
        raise click.ClickException(
            f"expected one Developer ID Application identity for {TEAM_ID} in the keychain, found {len(matches)}"
        )
    return matches[0]


@cli.command()
@click.argument("app", type=click.Path(exists=True, file_okay=False, path_type=Path))
@click.argument("output", type=click.Path(dir_okay=False, path_type=Path))
@click.option("--volume-name", default=APP_NAME, show_default=True, help="The name the mounted image shows in Finder.")
@click.option("--sign", is_flag=True, help="Sign the image with the team's Developer ID Application certificate.")
def dmg(app: Path, output: Path, volume_name: str, sign: bool) -> None:
    """Pack APP into the disk image people download from the website.

    The image opens to a Finder window with the app on the left, a link to
    Applications on the right, and the background from dmg/ between them
    showing which way to drag. dmgbuild writes the window's layout into the
    image itself, so this works the same on a CI runner with no Finder.
    """
    icon = app / "Contents/Resources/AppIcon.icns"
    if not icon.exists():
        raise click.ClickException(f"{icon} is missing, so the image would have no icon")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.unlink(missing_ok=True)
    settings = {
        # LZFSE compression: smaller than zlib and quick to open. It needs
        # macOS 10.11, far below the app's own minimum.
        "format": "ULFO",
        "files": [str(app)],
        "symlinks": {"Applications": "/Applications"},
        # The mounted volume shows the app's own icon.
        "icon": str(icon),
        "icon_locations": {app.name: DMG_APP_AT, "Applications": DMG_APPLICATIONS_AT},
        # No hide_extensions: it marks the bundle with Finder information,
        # which fails `codesign --verify --strict`. Finder hides ".app" anyway
        # unless someone has chosen to see every extension.
        #
        # dmgbuild finds background@2x.png beside it and joins the two.
        "background": str(HERE / "dmg/background.png"),
        # The height counts the title bar, which is 32 points on macOS 26 and
        # 27, so the background shows 400 points of its 420.
        "window_rect": ((200, 140), (640, 432)),
        "default_view": "icon-view",
        "icon_size": 112,
        "text_size": 13,
        "show_status_bar": False,
        "show_tab_view": False,
        "show_toolbar": False,
        "show_pathbar": False,
        "show_sidebar": False,
    }
    dmgbuild.build_dmg(str(output), volume_name, settings=settings)
    if sign:
        run("codesign", "--sign", developer_id_identity(), "--timestamp", output)
    click.echo(f"wrote {output}")


# --- appcast -------------------------------------------------------------------


def sparkle_tools() -> Path:
    """Sparkle's bin/ folder, downloaded once and checked against the pinned checksum."""
    pinned = re.search(
        r'repositoryURL = "https://github.com/sparkle-project/Sparkle";\s*'
        r"requirement = \{\s*kind = exactVersion;\s*version = ([\d.]+);",
        (PROJECT / "project.pbxproj").read_text(),
    )
    if not pinned or pinned[1] != SPARKLE_VERSION:
        raise click.ClickException(
            f"the app links Sparkle {pinned[1] if pinned else '(unknown)'}, but this script pins {SPARKLE_VERSION}"
        )
    cache = (
        Path(os.environ.get("RUNNER_TEMP") or Path.home() / "Library/Caches/errol-release")
        / f"Sparkle-{SPARKLE_VERSION}"
    )
    tools = cache / "bin"
    if (tools / "generate_appcast").exists():
        return tools
    cache.mkdir(parents=True, exist_ok=True)
    tarball = cache / f"Sparkle-{SPARKLE_VERSION}.tar.xz"
    url = f"https://github.com/sparkle-project/Sparkle/releases/download/{SPARKLE_VERSION}/Sparkle-{SPARKLE_VERSION}.tar.xz"
    click.echo(f"downloading {url}", err=True)
    with urllib.request.urlopen(url) as response:
        tarball.write_bytes(response.read())
    digest = hashlib.sha256(tarball.read_bytes()).hexdigest()
    if digest != SPARKLE_SHA256:
        tarball.unlink()
        raise click.ClickException(f"Sparkle {SPARKLE_VERSION} has checksum {digest}, expected {SPARKLE_SHA256}")
    with tarfile.open(tarball) as archive_file:
        archive_file.extractall(cache, filter="tar")
    return tools


def published_releases(limit: int) -> list[str]:
    """Tags of the newest published releases, leaving out drafts and prereleases."""
    listing = run(
        "gh", "release", "list", "--repo", GITHUB_REPO,
        "--exclude-drafts", "--exclude-pre-releases",
        "--limit", str(limit), "--json", "tagName",
        capture_output=True, text=True,
    )  # fmt: skip
    return [release["tagName"] for release in json.loads(listing.stdout)]


@cli.command()
@click.argument("archive_zip", metavar="ZIP", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option("--tag", required=True, help="The tag of the release the ZIP will be uploaded to, like v1.0.0.")
@click.option(
    "--out",
    type=click.Path(file_okay=False, path_type=Path),
    required=True,
    help="Where appcast.xml and the deltas go.",
)
@click.option(
    "--notes",
    type=click.Path(exists=True, dir_okay=False, path_type=Path),
    help="Release notes in Markdown, shown in the update window.",
)
@click.option(
    "--key-file",
    help="The private Sparkle key: a path, or - to read it from standard input. Without it, the key comes from the keychain.",
)
@click.option(
    "--previous", default=3, show_default=True, help="How many published releases to build delta updates from."
)
@click.option(
    "--include",
    multiple=True,
    type=click.Path(exists=True, dir_okay=False, path_type=Path),
    help="Another update ZIP to put in the feed, for a rehearsal that doesn't use GitHub.",
)
@click.option(
    "--download-url-prefix",
    help="Where the ZIP and deltas will be downloadable, ending in a slash. Defaults to the tag's release on GitHub.",
)
def appcast(
    archive_zip: Path,
    tag: str,
    out: Path,
    notes: Path | None,
    key_file: str | None,
    previous: int,
    include: tuple[Path, ...],
    download_url_prefix: str | None,
) -> None:
    """Write the update feed that offers ZIP, with deltas from earlier releases.

    The feed starts from the one in the newest published release, so earlier
    entries keep their own download links, and the new entry and its deltas
    point at TAG. Upload appcast.xml and every .delta file from OUT to that
    release alongside the ZIP.
    """
    tools = sparkle_tools()
    prefix = download_url_prefix or f"https://github.com/{GITHUB_REPO}/releases/download/{tag}/"
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as work_dir:
        work = Path(work_dir)
        for archive_file in (archive_zip, *include):
            shutil.copy2(archive_file, work / archive_file.name)
        if notes:
            shutil.copy2(notes, work / f"{archive_zip.stem}.md")
        tags = published_releases(previous) if download_url_prefix is None else []
        for index, earlier in enumerate(tags):
            # Only the newest feed is wanted; the ZIPs are there for deltas.
            patterns = ["--pattern", f"{APP_NAME}-*.zip"] + (["--pattern", "appcast.xml"] if index == 0 else [])
            fetched = run(
                "gh", "release", "download", earlier, "--repo", GITHUB_REPO, "--dir", work, "--skip-existing", *patterns,
                check=False,
            )  # fmt: skip
            if fetched.returncode != 0:
                click.secho(f"couldn't download from {earlier}; the feed won't have its deltas", fg="yellow", err=True)
        for dsyms in work.glob("*-dSYMs.zip"):
            dsyms.unlink()

        command = [
            tools / "generate_appcast",
            "--download-url-prefix", prefix,
            "--link", WEBSITE,
            "--full-release-notes-url", f"https://github.com/{GITHUB_REPO}/releases",
            "--maximum-deltas", str(previous),
        ]  # fmt: skip
        if key_file:
            command += ["--ed-key-file", key_file]
        command.append(work)
        # With --key-file -, the key arrives on this process's standard input
        # and passes straight through, so it's never written to disk.
        run(*command)

        feed = work / "appcast.xml"
        text = feed.read_text()
        info = plistlib.loads(
            subprocess.run(
                ["unzip", "-p", str(archive_zip), f"{APP_NAME}.app/Contents/Info.plist"],
                capture_output=True,
                check=True,
            ).stdout
        )
        build = info["CFBundleVersion"]
        if f"{prefix}{archive_zip.name}" not in text or f"<sparkle:version>{build}</sparkle:version>" not in text:
            raise click.ClickException(f"the feed has no entry for build {build} at {prefix}{archive_zip.name}")
        shutil.copy2(feed, out / "appcast.xml")
        deltas = sorted(work.glob("*.delta"))
        for delta in deltas:
            shutil.copy2(delta, out / delta.name)
    click.echo(f"wrote {out / 'appcast.xml'} and {len(deltas)} delta update(s) for build {build}")


# --- rehearse ------------------------------------------------------------------


REHEARSAL_PORT = 8765


def development_identity(app: Path) -> str:
    """The certificate an app is signed with, as codesign names it."""
    details = run("codesign", "-dv", "--verbose=2", app, capture_output=True, text=True).stderr
    authority = re.search(r"^Authority=(.+)$", details, re.MULTILINE)
    if not authority or not authority[1].startswith("Apple Development:"):
        raise click.ClickException(f"{app} isn't signed for development; archive it with --signing development")
    return authority[1]


def trust_key(app: Path, public_key: str) -> None:
    """Swaps the app's Sparkle key for the rehearsal's and signs it again.

    Only the outer bundle changes, so only it is signed again, with the same
    certificate, entitlements, and hardened runtime as before. Its designated
    requirement doesn't change, so neither does its Accessibility grant.
    """
    run("plutil", "-replace", "SUPublicEDKey", "-string", public_key, app / "Contents/Info.plist")
    run(
        "codesign", "--force", "--sign", development_identity(app),
        "--options", "runtime", "--preserve-metadata=entitlements,flags",
        "--generate-entitlement-der", app,
    )  # fmt: skip
    run("codesign", "--verify", "--deep", "--strict", app)


@cli.command()
@click.argument("old", type=click.Path(exists=True, file_okay=False, path_type=Path))
@click.argument("new", type=click.Path(exists=True, file_okay=False, path_type=Path))
@click.option(
    "--work",
    type=click.Path(file_okay=False, path_type=Path),
    required=True,
    help="A scratch folder for the rehearsal.",
)
@click.option("--serve/--no-serve", default=True, show_default=True, help="Serve the feed until interrupted.")
def rehearse(old: Path, new: Path, work: Path, serve: bool) -> None:
    """Rehearse an update from OLD to NEW on this Mac, with no credentials.

    OLD and NEW are two builds from `archive --signing development`, NEW with
    the higher build number. This signs the update with a throwaway Sparkle key
    that both copies are made to trust, writes a feed for NEW with a delta from
    OLD, installs OLD in WORK/install, and serves the feed from
    http://127.0.0.1:8765. Installed copies of Errol only read it once told to:

        defaults write com.t7m8.Errol SUFeedURL http://127.0.0.1:8765/appcast.xml

    which is also how a prerelease is tested against its own feed. Delete the
    setting afterwards, since every build of Errol on this Mac shares it.
    """
    shutil.rmtree(work, ignore_errors=True)
    feed_dir, install, key_dir = work / "feed", work / "install", work / "key"
    for folder in (feed_dir, install, key_dir):
        folder.mkdir(parents=True)

    # Sparkle keeps a private key as the base64 of its 32-byte seed.
    seed = os.urandom(32)
    public = Ed25519PrivateKey.from_private_bytes(seed).public_key()
    public_key = base64.b64encode(
        public.public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    ).decode()
    private_file = key_dir / "private.key"
    private_file.write_text(base64.b64encode(seed).decode())
    private_file.chmod(0o600)

    versions = []
    for label, app in (("old", old), ("new", new)):
        copy = work / label / app.name
        run("ditto", app, copy)
        trust_key(copy, public_key)
        info = plistlib.loads((copy / "Contents/Info.plist").read_bytes())
        versions.append((copy, info["CFBundleShortVersionString"], int(info["CFBundleVersion"])))
    (old_app, old_version, old_build), (new_app, new_version, new_build) = versions
    if new_build <= old_build:
        raise click.ClickException(f"NEW is build {new_build}, which doesn't come after OLD's {old_build}")

    old_zip = work / f"{APP_NAME}-{old_version}.zip"
    new_zip = work / f"{APP_NAME}-{new_version}.zip"
    zip_app.callback(app=old_app, output=old_zip)
    zip_app.callback(app=new_app, output=new_zip)
    dmg.callback(app=old_app, output=feed_dir / f"{APP_NAME}-{old_version}.dmg", volume_name=APP_NAME, sign=False)
    prefix = f"http://127.0.0.1:{REHEARSAL_PORT}/"
    appcast.callback(
        archive_zip=new_zip,
        tag=f"v{new_version}",
        out=feed_dir,
        notes=None,
        key_file=str(private_file),
        previous=3,
        include=(old_zip,),
        download_url_prefix=prefix,
    )
    shutil.copy2(new_zip, feed_dir / new_zip.name)
    run("ditto", old_app, install / old_app.name)

    click.echo(
        f"""
Ready to rehearse the update from {old_version} (build {old_build}) to {new_version} (build {new_build}).

  1. Quit any other copy of Errol, since they share a bundle identifier.
  2. Point Errol at the rehearsal's feed:
       defaults write com.t7m8.Errol SUFeedURL {prefix}appcast.xml
  3. Open {install / old_app.name}
     and choose Check for Updates from its menu. Try it during a run too.
  4. Afterwards:
       defaults delete com.t7m8.Errol SUFeedURL
"""
    )
    if serve:
        click.echo(f"serving {feed_dir} at {prefix} until interrupted")
        run(sys.executable, "-m", "http.server", str(REHEARSAL_PORT), "--bind", "127.0.0.1", "--directory", feed_dir)


if __name__ == "__main__":
    sys.exit(cli())
