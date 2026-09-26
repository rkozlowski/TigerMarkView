# Network share acceptance

Every image under "Share" names `\\127.0.0.1\tmvprobe`, a share in this guest whose every file access
is audited. None of them may be touched. The local and web images must still load.

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
