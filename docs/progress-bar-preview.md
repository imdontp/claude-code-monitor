# Progress Bar Preview

The active statusline now uses the solid-block bar with 12 segments. The examples below use the same 12-segment width.

Color palette for the active bar:

- 0-59%: green
- 60-74%: yellow
- 75-89%: orange
- 90-100%: red
- empty segments: gray

## 1. Solid block (active)

```text
41% █████░░░░░░░
62% ███████░░░░░
88% ███████████░
```

Example layout:

```text
Context: 41% █████░░░░░░░ (82k/200k)
5h:      62% ███████░░░░░ | reset in 2h13m
Weekly:  18% ██░░░░░░░░░░ | reset Tue 09:00
```

## 2. Powerline

```text
41% ▰▰▰▰▰▱▱▱▱▱▱▱
62% ▰▰▰▰▰▰▰▱▱▱▱▱
88% ▰▰▰▰▰▰▰▰▰▰▰▱
```

Lightweight and UI-like, but it depends more on terminal font support.

## 3. Shade block

```text
41% ▓▓▓▓▓░░░░░░░
62% ▓▓▓▓▓▓▓░░░░░
88% ▓▓▓▓▓▓▓▓▓▓▓░
```

Softer than the solid bar, but the filled/empty boundary can be less crisp on some fonts.

## 4. Thin segment

```text
41% ▮▮▮▮▮▯▯▯▯▯▯▯
62% ▮▮▮▮▮▮▮▯▯▯▯▯
88% ▮▮▮▮▮▮▮▮▮▮▮▯
```

Compact and visually light.

## 5. Circle

```text
41% ●●●●●○○○○○○○
62% ●●●●●●●○○○○○
88% ●●●●●●●●●●●○
```

Friendly, but less precise-looking for a usage meter.

## 6. ASCII fallback

```text
41% #####-------
62% #######-----
88% ###########-
```

Best compatibility option for terminals that do not render Unicode reliably.

The bar applies one semantic color to all filled segments for the current percentage; empty segments remain gray. The selected style is independent from this color logic.
