# Network share acceptance

Every image under "Share" names a share in this guest whose every file access is audited:
`\\127.0.0.1\tmvprobe` directly or through a local symbolic link, and `\\127.0.0.1\tmvmapped` through
the mapped drive `Z:` and the aliased drive `Y:`. None of them may be touched. The local and web images
must still load.

## Still loading

![Shares web image](http://127.0.0.1:47631/img/shares-web.png)

![Relative local image](local.png)

![Absolute local image](file:///C:/TigerMarkViewAcceptance/documents/local.png)

<img src="file:///C:/TigerMarkViewAcceptance/documents/local.png" alt="Absolute HTML local image">

## Share

<img src="\\127.0.0.1\tmvprobe\html-backslash.png" alt="Backslash share image">

<img src="//127.0.0.1/tmvprobe/html-slash.png" alt="Slash share image">

<img src="file://127.0.0.1/tmvprobe/html-file.png" alt="File URL share image">

<img src="file:////127.0.0.1/tmvprobe/html-file-four.png" alt="Four-slash share image">

<img src="file:///%5C%5C127.0.0.1%5Ctmvprobe%5Chtml-encoded.png" alt="Encoded share image">

![Markdown share image](//127.0.0.1/tmvprobe/markdown-slash.png)

![Markdown escaped share image](<\\\\127.0.0.1\\tmvprobe\\markdown-backslash.png>)

<div style="background-image: url('//127.0.0.1/tmvprobe/css-background.png'); width: 48px; height: 48px">CSS share background</div>

<a href="file://127.0.0.1/tmvprobe/same-href.png" style="background-image:url(file://127.0.0.1/tmvprobe/same-href.png);display:block;width:48px;height:48px">Link with matching background</a>

<img src="file:///Z:/mapped.png" alt="Mapped network drive image">

<img src="file:///Y:/boundary.png" alt="Substituted network drive image">

<img src="///Y:/boundary.png" alt="Scheme-less substituted drive">

<img src="/Y|/boundary.png" alt="Legacy drive separator">

<img src="file:/Y:/boundary.png" alt="Single-slash file URI">

<img src="file:///Y%3a/boundary.png" alt="Encoded drive separator">

<img src="remote-link/boundary.png" alt="Local symlink to network image">

<svg><path fill="url(file://127.0.0.1/tmvprobe/paint.svg#x)" d="M0 0h20v20z"></path></svg>
