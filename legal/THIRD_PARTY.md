# Third-party code

## Lua 5.4.9 (vendored in `Sources/CLua`)

Copyright (C) 1994-2026 Lua.org, PUC-Rio. MIT License.
Source: https://www.lua.org/ftp/lua-5.4.9.tar.gz (SHA-256 `2335b6c582a52654f94612bf10d2f4672805d05329aa6568b1d8cd9e5c6fb8e6`).
`lua.c` and `luac.c` (the standalone programs) are not included. Other files are unchanged.

To update it:

1. Find the latest `lua-5.4.N.tar.gz` on https://www.lua.org/ftp/ and its SHA-256 on that page.
2. Download it into a new empty folder outside the repository, and check that `shasum -a 256` gives the published hash.
3. Copy every `.c` and `.h` file of its `src/` folder over the file of the same name in `Sources/CLua/`, except `lua.c`, `luac.c` and `lua.hpp`. `lauxlib.h`, `lua.h`, `luaconf.h` and `lualib.h` live in `Sources/CLua/include/`. No file is edited.
4. Run `swift build` and `swift test`, then change the version, the URL and the hash here, and in `Package.swift`, `README.md` and `docs/src/content/docs/development.md`.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## AeroSpace (MIT)

Used as the reference for the emulated workspaces (windows of hidden workspaces parked in a screen corner), the
per-application Accessibility threads, the `size, position, size` frame order, and the command and socket design. The
code in this package is written for wm; the behaviour follows AeroSpace.

```
MIT License

Copyright (c) 2023 Nikita Bobko

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## paneru (MIT, https://github.com/karinushka/paneru)

Used as the reference for the scrolling strip in `Sources/Core/ScrollingEngine.swift` (columns, minimal-shift scrolling,
centring modes, parked slivers), and the frame-rate independent ease-out in `Sources/Core/Animator.swift`. Ribbon.app, the commercial app built on paneru,
was only inspected to learn how it works; none of its code or assets are used.

```
MIT License

Copyright (c) 2025 Karinushka@github

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Dinky (MIT, https://github.com/mikker/Dinky)

The native workspaces (`Sources/PrivateApi/Spaces.c`, `Sources/Core/SpaceSwitcher.swift`) follow how Dinky does it: a synthetic Dock
swipe to switch desktops (with the IOHID payload that macOS 27 reads), the bridged `SLSBridgedMoveWindowsToManagedSpaceOperation` found
through the symbol table of SkyLight, and a switcher that keeps one request in flight for each display. Dinky has these from mimi,
bobrwm and yabai. The code was written again for wm, in C and Swift, from reading Dinky; the license is kept here for that reason.

```
MIT License

Copyright (c) 2026 Mikkel Malmberg

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
