# Third-party notices

Debrify is licensed under the GNU Affero General Public License v3 (see `LICENSE`).
Dart and Flutter packages it depends on carry their own licenses in their package
sources. This file lists bundled native libraries whose licenses ask for a notice
beyond that.

## libsmb2

SMB2/3 client library, used to copy finished recordings to an SMB network share.

- Copyright (C) 2016 by Ronnie Sahlberg <ronniesahlberg@gmail.com>.
  Portions copyright 2017 to Primary Data Inc.
- License: GNU Lesser General Public License, version 2.1 or (at your option) any
  later version. Full text: [`licenses/LGPL-2.1.txt`](licenses/LGPL-2.1.txt).
- How it is included: a separate, dynamically loaded shared library (for example
  `libsmb2.so` on Android). It is the prebuilt `libsmb2-r8` release bundled, and
  verified by SHA-256, by the [`dart_smb2`](https://pub.dev/packages/dart_smb2)
  package (0.1.3, BSD-3-Clause): a libsmb2 build with patches by the `dart_smb2`
  author. Debrify makes no further changes to it, apart from the symbol stripping
  that standard platform builds apply, and calls it through `dart_smb2`'s FFI
  bindings. Bundled on Android, Windows, Linux and macOS (and iOS, where it is
  unused); not on tvOS.
- Corresponding source: the patches and build scripts, with the pinned upstream
  libsmb2 revision, are published at <https://github.com/ales-drnz/libsmb2-scripts>
  (release `libsmb2-r8`, whose `manifest.json` names the exact commit). Upstream
  libsmb2 is at <https://github.com/sahlberg/libsmb2>.
- Replacing the library: Debrify's own source is public under the AGPL, so you can
  rebuild Debrify against your own build of a compatible libsmb2 (same ABI), as
  the LGPL allows.

### libdcerpc (part of libsmb2)

libsmb2's DCE/RPC component is licensed under the 2-Clause BSD License:

```
Copyright (C) 2018 by Ronnie Sahlberg <ronniesahlberg@gmail.com>

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this
   list of conditions and the following disclaimer in the documentation and/or
   other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
