# Packaging a release

How the macOS disk image is built, signed and notarised. The Windows build has its
own page, [`WINDOWS-BUILD.md`](WINDOWS-BUILD.md).

```
DMG=yes tools/package_macos_app.sh
```

That produces `Incursion.app` inside a disk image. It builds twice on purpose: a
developer binary to compile the game module, then a shipping binary without the
resource compiler, because the compiler carries a GPLv2 runtime that must not be
distributed. It bundles SDL2, signs, notarises and staples **both the app and the
image**, and `tools/check_app.sh` refuses to let a broken one out.

`tools/package_macos.sh` still exists and builds the older plain-folder layout. Do
not ship that: a bare executable cannot be approved by Gatekeeper no matter how
correctly it is signed, which is what broke the first release.

**Anyone can run this; not everyone can produce a distributable result.** Without
an Apple signing identity the script prints `SKIPPED`, produces an unsigned image,
and carries on. That image runs fine on the machine that built it, because a file
you create yourself carries no quarantine attribute — which is exactly why this
class of bug is invisible locally. It will be refused on any machine that
downloads it.

To produce something another Mac will launch you need:

- a paid Apple Developer Program membership;
- a **Developer ID Application** certificate. An *Apple Development* certificate
  cannot sign anything distributed outside the App Store — different type, and the
  distinction is easy to lose a day to;
- notarisation credentials. Run `tools/setup_notary.sh` once, in a real terminal,
  and it stores an app-specific password at `~/.config/incursion/notary.env`,
  mode 600, after validating it against Apple.

Use `setup_notary.sh` rather than `notarytool store-credentials`. A keychain
profile is only readable by processes on the keychain item's ACL, so a release
built from anything other than the terminal that created the profile fails with
`No Keychain password item found` — which means *found but not permitted*, and
reads like a missing credential. A file has no ACL.

## Which tag marks which download

`master` is the development tip. The `release-4` tag marks the release itself,
and the Linux and Steam Deck tarballs were built from it. The macOS and Windows
downloads are newer: both need the mingw-w64 portability work that landed after
the tag, which the `release-4-windows` tag marks. None of that work changes
behaviour on macOS or Linux, so all four downloads are the same game. The `release-1` tag marks this fork's first release, but the
release-1 image was rebuilt after that tag, to carry the module-load and
Gatekeeper fixes described in [`FIXED.md`](FIXED.md); that tag is not a
byte-for-byte match for it.
