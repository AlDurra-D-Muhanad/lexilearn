# The new logo

**The user supplied `C:\Users\user\Desktop\lexilearn notes\New Logo.png`:**
an open book with a gold cover, a gold speech bubble carrying «ضA», on a navy
rounded square with a gold border. 991 × 980, RGBA.

**The assets are already produced. They are in `assets/icon/` and they are
committed artefacts, not something to regenerate by hand.**

| file | what it is | verified |
|---|---|---|
| `assets/icon/app_icon.png` | 1024 × 1024, **opaque**, the artwork centred-**cropped** to the smaller side and scaled — **cropped, not stretched**, because stretching a book changes it | centre `#030D24`, corner `#0C1731`, alpha 255 |
| `assets/icon/app_icon_foreground.png` | 1024 × 1024, the artwork at **72/108 = 66.7%** of the canvas, centred, on transparency | corner alpha 0 |
| `assets/icon/app_icon_background.png` | 1024 × 1024, a flat swatch | `#0B1630` |

**The navy is `#0B1630`, sampled from the logo's own background** at (24, 24) — not chosen. The
old icon was an opaque purple square (`#885CF6` at both the corner and the centre), **so the
old brand colour was baked into the app's icon.**

## What still has to change

**1. `pubspec.yaml`'s `flutter_launcher_icons` block.**
```
image_path:                       "assets/icon/app_icon.png"          (unchanged)
adaptive_icon_background:          "#0B1630"        was "#885CF6" -- the OLD brand
adaptive_icon_foreground:          "assets/icon/app_icon_foreground.png"
adaptive_icon_background_image:   "assets/icon/app_icon_background.png"
adaptive_icon_foreground_inset:    0                (the foreground is already in the safe zone)
```
**The background must change from purple to the logo's own navy.** Leaving it purple would
paint the old brand into the corners of the icon on the user's home screen.

**2. Re-run `dart run flutter_launcher_icons`** to regenerate the Android launcher resources.

**3. The in-app mark — DO NOT TOUCH IT.** The user ruled: «العلامةِ داخلَ التطبيق ابقها كما هي لا تغيرها
بتغيير اللوغو بدل اللوغو فقط». The logo is the **launcher icon** and nothing else.

So `_BookMark` in `lib/ui/home/home_screen.dart` **stays exactly as it is**: the circular
gradient disc, the 1.5px gold border, and `Icons.menu_book_rounded` at 22px. **Do not
replace it with the artwork, and do not make the disc a square to match the artwork's shape.**
The artwork is a rounded square and the in-app mark is a disc; that difference is the user's
decision and it stands.

**A consequence worth stating: the launcher icon does not appear in any golden.** The
home screen's mark is an `Icon` widget, not the launcher asset, so **no golden should
change for this work.** If one does, something else changed with it — find out what.

## Rules
- **The gold is `#F3AC43`; the logo's own border gold measures `#F4CF6C`** — a different gold,
  and the difference is the artwork's, not a token's. Do not "correct" it.
- Every colour in `lib/ui/` still comes from a token. The artwork is an **image**, so it
  carries its own colours by definition — but no new literal colour may appear in code.
- The goldens must be regenerated for the home screen, in both modes, and the census must pass
  with its two baseline tables re-measured from a standalone sweep over the committed PNGs.
