/// Clipboard HTML as apps write it, for the paste tests.
library;

/// Chromium's style on the copied part's outer elements: the page's
/// colors and font, which a paste must leave out.
const _chromiumStyle =
    'color: rgb(204, 204, 204); font-family: -apple-system, '
    'BlinkMacSystemFont, &quot;Segoe WPC&quot;, &quot;Segoe UI&quot;, '
    'sans-serif; font-size: 13px; font-style: normal; font-weight: 400; '
    'letter-spacing: normal; text-align: start; text-indent: 0px; '
    'text-transform: none; white-space: normal; word-spacing: 0px; '
    'background-color: rgb(31, 31, 31); text-decoration-thickness: initial; '
    'text-decoration-style: initial; text-decoration-color: initial;';

/// A Claude Code answer (a webview in VS Code, so Chromium) copied on
/// Windows: "HTML Format" with its description, the page around the
/// copied part, Chromium's `<span> </span>` spaces, and trailing null
/// bytes.
const claudeCodeCopy =
    'Version:0.9\r\n'
    'StartHTML:0000000105\r\n'
    'EndHTML:0000009999\r\n'
    'StartFragment:0000000141\r\n'
    'EndFragment:0000009963\r\n'
    '<html>\r\n<body>\r\n<!--StartFragment-->'
    '<p style="$_chromiumStyle">Yes. Prd is now at its starting point: people '
    'can sign in, see their projects with their setup, and the app has '
    'everything it needs to run.</p>'
    '<p style="$_chromiumStyle"><strong>What prd has:</strong>'
    '<span style="$_chromiumStyle"> </span>the whole app (domains, '
    'picklists, data views, reports, app pages, both apps, roles and '
    'reference data), the 8 projects with their setup, 29 users with roles '
    'and memberships, and 15 signatures.</p>'
    '<p style="$_chromiumStyle"><strong>What\'s left</strong></p>'
    '<p style="$_chromiumStyle"><strong>1. Project chart and monitoring '
    'settings.</strong><span style="$_chromiumStyle"> </span>These are '
    'project settings rather than daily data, but none of them are in prd '
    'yet:</p>'
    '<table style="$_chromiumStyle"><thead><tr><th>Setting</th>'
    '<th>Projects</th></tr></thead><tbody>'
    '<tr><td>Dredge chart (background image, cell grid, dredge shapes)</td>'
    '<td>Fountain Lake, Kalamazoo, Lake Pepin, Penobscot, Torch Lake, '
    'Weigand</td></tr>'
    '<tr><td>Water and air monitoring settings, Dust Log settings</td>'
    '<td>the same 6 projects</td></tr>'
    '<tr><td>Placement chart</td><td>Torch Lake and Weigand</td></tr>'
    '</tbody></table>'
    '<p style="$_chromiumStyle">These settings live in the<span> </span>'
    '<code>6_dredge</code>,<span> </span><code>7_monitoring</code>'
    '<span> </span>and<span> </span><code>placement</code><span> </span>'
    'migration scripts.</p>'
    '<p style="$_chromiumStyle"><strong>2. Live monitoring (the monitoring '
    'pull).</strong><span> </span>It needs the settings from item 1, '
    'plus:</p>'
    '<ul style="$_chromiumStyle">'
    '<li>the vendor secrets in prd:<span> </span>'
    '<code>app-envdaily-hydrovu-*</code>,<span> </span>'
    '<code>app-envdaily-wqdatalive-api-key</code><span> </span>and'
    '<span> </span><code>app-envdaily-ecomzen-*</code>;</li>'
    '<li>secret rows for those vendor secrets;</li>'
    '<li>a schedule.</li></ul>'
    '<p style="$_chromiumStyle"><strong>3. Small items:</strong></p>'
    '<ul style="$_chromiumStyle"><li>Run<span> </span><code>verify</code>'
    '<span> </span>on users 3 and users 5.</li></ul>'
    '<br class="Apple-interchange-newline">'
    '<!--EndFragment-->\r\n</body>\r\n</html>\u0000\u0000';

/// The plain text Chromium puts beside [claudeCodeCopy]: no table, no
/// bullets, no bold, and two lines that start like a numbered list.
const claudeCodeCopyText =
    'Yes. Prd is now at its starting point.\n'
    'What prd has: the whole app.\n'
    "What's left\n"
    '1. Project chart and monitoring settings. These are project settings.\n'
    'Setting\tProjects\n'
    'Placement chart\tTorch Lake and Weigand\n'
    '2. Live monitoring (the monitoring pull). It needs the settings, plus:\n'
    'the vendor secrets in prd: app-envdaily-hydrovu-*, '
    'app-envdaily-wqdatalive-api-key and app-envdaily-ecomzen-*;\n'
    'a schedule.';

/// VS Code's editor copying a Markdown file: the raw text, colored, in a
/// `white-space: pre` box, one `<div>` per line.
const vsCodeEditorCopy =
    '<meta charset="utf-8"><div style="color: #cccccc;background-color: '
    '#1f1f1f;font-family: Consolas, \'Courier New\', monospace;font-weight: '
    'normal;font-size: 14px;line-height: 19px;white-space: pre;">'
    '<div><span style="color: #569cd6;font-weight: bold;">## Also</span>'
    '</div><div><span style="color: #6796e6;">-</span><span> </span>'
    '<span style="color: #569cd6;font-weight: bold;">**ripe**</span>'
    '<span> tomatoes</span></div><div><br></div>'
    '<div><span style="color: #6796e6;">-</span><span> bread</span></div>'
    '</div>';

/// The plain text beside [vsCodeEditorCopy].
const vsCodeEditorCopyText = '## Also\n- **ripe** tomatoes\n\n- bread';

/// Google Docs: everything inside `<b style="font-weight:normal">`, bold
/// marked with `font-weight:700`.
const googleDocsCopy =
    '<meta charset="utf-8"><b style="font-weight:normal;" '
    'id="docs-internal-guid-1234"><p dir="ltr" style="line-height:1.38;">'
    '<span style="font-size:11pt;font-family:Arial,sans-serif;color:#000000;'
    'background-color:transparent;font-weight:400;">Plain then </span>'
    '<span style="font-size:11pt;font-family:Arial,sans-serif;color:#000000;'
    'background-color:transparent;font-weight:700;">bold</span>'
    '<span style="font-size:11pt;font-family:Arial,sans-serif;color:#000000;'
    'background-color:transparent;font-weight:400;font-style:italic;"> and '
    'italic</span></p></b>';
