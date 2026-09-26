# Code acceptance

```csharp
public sealed class Greeter
{
    private const int Max = 42; // highlighted
}
```

The blocks below are hostile source code. It must stay visible text: if any of it became markup, the
image it names would be requested from `/exfil/`, which the request logger would record.

```csharp
var s = "</span></code></pre><img src=http://127.0.0.1:47631/exfil/code-csharp-img>";
```

```html
<img src="http://127.0.0.1:47631/exfil/code-html-img" onerror="fetch('http://127.0.0.1:47631/exfil/code-html-onerror')">
```

```javascript
</span><script>new Image().src = 'http://127.0.0.1:47631/exfil/code-javascript';</script>
```

```sql
SELECT '<a href="javascript:fetch(''http://127.0.0.1:47631/exfil/code-sql'')">x</a>';
```

```text
<script>fetch('http://127.0.0.1:47631/exfil/code-plain')</script>
```
