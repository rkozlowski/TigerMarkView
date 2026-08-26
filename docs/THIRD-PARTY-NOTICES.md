# Third-party notices

TigerMarkView is released under the MIT License; see the root `LICENSE` file or
**Help > About TigerMarkView > License**.

The Windows application and `tiger-mark` use the following third-party components. Package names,
publishers, and licence identifiers are taken from the package metadata used by this repository.

| Component | Publisher / copyright holder | Licence |
|---|---|---|
| [Markdig](https://github.com/xoofx/markdig) | Alexandre Mutel | BSD 2-Clause |
| [ColorCode.Core / ColorCode-Universal](https://github.com/CommunityToolkit/ColorCode-Universal) | .NET Foundation and Contributors | MIT |
| [Avalonia package family](https://avaloniaui.net/) | The AvaloniaUI Project / Avalonia Team | MIT |
| [Avalonia.Controls.WebView](https://avaloniaui.net/) | AvaloniaUI OÜ | MIT |
| Avalonia.Angle.Windows.Natives | The ANGLE Project Authors | BSD 3-Clause |
| [SkiaSharp and Windows native assets](https://github.com/mono/SkiaSharp) | Xamarin, Inc. and Microsoft Corporation | MIT |
| [HarfBuzzSharp and Windows native assets](https://github.com/mono/SkiaSharp) | Xamarin, Inc. and Microsoft Corporation | MIT |
| MicroCom.Runtime | Nikita Tsukanov | MIT |
| Tmds.DBus.Protocol | Tom Deseyn | MIT |
| [Microsoft Edge WebView2 SDK](https://aka.ms/webview) | Microsoft Corporation | BSD 3-Clause |
| [Fluent UI System Icons](https://github.com/microsoft/fluentui-system-icons) | Microsoft Corporation | MIT |
| [ItTiger.TigerCli](https://www.ittiger.net/projects/tigercli/) | IT Tiger | MIT |
| [ItTiger.Core](https://www.ittiger.net/projects/tigercli/) | IT Tiger | MIT |
| [Microsoft.Extensions.Logging.Abstractions](https://dot.net/) | Microsoft Corporation | MIT |
| [Microsoft.Extensions.DependencyInjection.Abstractions](https://dot.net/) | Microsoft Corporation | MIT |

Markdig converts Markdown to HTML. ColorCode.Core supplies language grammars for optional syntax
highlighting; TigerMarkView supplies the colour palettes. Avalonia, SkiaSharp, HarfBuzzSharp,
MicroCom.Runtime, Tmds.DBus.Protocol, ANGLE, and Avalonia.Controls.WebView form the UI and WebView
integration. The WebView2 SDK displays rendered documents and produces PDFs. TigerMarkView vendors a
small subset of Fluent UI System Icons as vector geometry.

TigerCli provides command parsing, generated help, error and exit-code handling for `tiger-mark`.
Its runtime dependencies include ItTiger.Core and the two Microsoft.Extensions abstractions packages.
They are not included in the desktop installer.

The dedicated copies in `assets/licenses/` retain the exact upstream notices for ColorCode-Universal
and Fluent UI System Icons.

## MIT License

Applies to ColorCode.Core, the Avalonia package family, Avalonia.Controls.WebView, SkiaSharp,
HarfBuzzSharp, MicroCom.Runtime, Tmds.DBus.Protocol, Fluent UI System Icons, ItTiger.TigerCli,
ItTiger.Core, and the two
Microsoft.Extensions abstractions packages. Copyright is held by the respective parties in the table
above. ColorCode.Core is Copyright (c) .NET Foundation and Contributors. The Avalonia package
metadata is Copyright 2013-2026 © The AvaloniaUI Project, and Avalonia.Controls.WebView is Copyright
2019-2026 © AvaloniaUI OÜ. The SkiaSharp and HarfBuzzSharp package licence names Xamarin, Inc.
(2015-2016) and Microsoft Corporation (2017-2018). MicroCom.Runtime is Copyright 2021 © Nikita
Tsukanov; Tmds.DBus.Protocol names Tom Deseyn as copyright holder. Fluent UI System Icons is
Copyright (c) 2020 Microsoft Corporation. TigerCli and ItTiger.Core are Copyright (c) 2026 IT Tiger.

```text
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

## BSD 2-Clause License

Applies to Markdig. Copyright © Alexandre Mutel. All rights reserved.

```text
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## BSD 3-Clause License

Applies to Avalonia.Angle.Windows.Natives (Copyright 2018 The ANGLE Project Authors; all rights
reserved) and the Microsoft Edge WebView2 SDK (Copyright (C) Microsoft Corporation; all rights
reserved).

```text
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## WebView2 Runtime

TigerMarkView requires the Microsoft Edge WebView2 Runtime on the machine, but does not redistribute
it. The separate WebView2 SDK files included with the application are covered by the BSD 3-Clause
notice above.
