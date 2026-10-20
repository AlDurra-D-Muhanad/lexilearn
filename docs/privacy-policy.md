# Privacy policy — LexiLearn

**Last verified: 20 October 2026, against a release build made that day.**

## The short version

**LexiLearn has no internet access, and it is built so that it cannot have any.**

- **No network permission.** The merged `AndroidManifest.xml` inside the release APK declares
  **no `INTERNET`, no `ACCESS_NETWORK_STATE`, no `READ_EXTERNAL_STORAGE`, and no
  `MANAGE_EXTERNAL_STORAGE`.** This is not a setting the app can be talked out of; the
  permission is not in the binary.
- **No accounts.** There is no sign-in, no registration, no email address and no user
  identifier. The app cannot know who you are because it never asks.
- **No analytics, no telemetry, no crash reporting, no advertising.** Nothing is collected,
  because nothing can leave the device.
- **No network code.** The application has no HTTP client, no socket, and no third-party
  service. The one outbound capability it has is handing a `https` link to another
  application — the Telegram contact, via the platform's own intent mechanism — which is a
  request to *another* app to do something, not a request from this one to a server.

## What stays on your device

Everything, and it is all local to the application:

| | |
|---|---|
| **Your progress** | which words you have practised, and which you have mastered |
| **Your favourites** | the words you have starred |
| **Your settings** | the theme you chose, and the pack you are reading |
| **The dictionary** | 31,600 English-Arabic entries, shipped inside the application |

**None of it is transmitted, uploaded, backed up to a server, or synchronised between
devices.** The application works with the network switched off, with airplane mode on, and
on a device that has never been online.

## What you can do with your data

- **Export it.** The backup feature produces a JSON file on your device, containing your
  favourites and your progress. You can read it, copy it, or delete it.
- **Delete it.** Uninstalling the application removes the application database and the
  copied dictionary with it. Nothing is left behind on a server, because there is no
  server.
- **Move it.** The backup file can be restored on another device, by importing it there.

## The dictionary's own licence

The dictionary is not the application's own work. It is built from three open sources, and
its licence requires that they be named. **The application names them in full, in the app
itself**, under the three-dot menu, in *المصادر والنسب* — including the licence of each
source separately, because they are not the same licence.

The full attribution, read from the upstream project's own configuration rather than
paraphrased, is in [`docs/dictionary-attribution.md`](dictionary-attribution.md).

## How this was verified

The offline claim is a legal claim, so it is checked against the artefact that ships and
not against the source tree.

`tool/verify_release_offline.ps1` builds the arm64 release APK, then reads the **merged**
`AndroidManifest.xml` from inside it, by **two independent measurements**:

1. `aapt2 dump permissions` — authoritative, parsed from the binary AXML;
2. a raw UTF-16LE byte scan of the APK — which needs no SDK at all.

Both must pass. A single parser can be wrong in a way that agrees with itself; these two
cannot agree by accident.

The gate is also proven able to fail: a canary APK carrying the bytes of
`android.permission.INTERNET` makes it exit non-zero with `OFFLINE GATE FAILED`. **A check
that cannot fail is not a check.**

The result of the last run, against the release build of 20 October 2026:

```
APK        : app-arm64-v8a-release.apk
size       : 31,441,669 B = 29.99 MiB = 31.44 MB
budget     : 35.00 MB -> within

check 1    : aapt2 dump permissions
             com.lexilearn.lexilearn.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
check 2    : raw UTF-16LE byte scan of the APK
             none of the four appear anywhere in the artefact

OFFLINE GATE PASSED
```

The only permission the merged manifest carries is AndroidX's own
`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, which is a self-scoped internal permission
that lets a library receive its own broadcasts. **It grants access to nothing outside the
application.**

## If you have a question

The developer's contact is in the three-dot menu of every screen, under *تواصل عبر تيليغرام*.
