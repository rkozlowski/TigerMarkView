<#
    .SYNOPSIS
    TigerWinLab guest helper: what the Windows shell of the signed-in user says about Markdown files.

    .DESCRIPTION
    Runs as the interactive standard user (through the desktop session's `run` command), because
    per-user file associations, Open with, and Add/Remove Programs live in that user's own hive.
    Windows PowerShell 5.1. Paths come from a JSON request file rather than the command line, which
    the desktop agent passes without quoting.

      shell.ps1 probe <request.json> <result.json>
        Writes the user's association state: the .md and .markdown class keys, OpenWithProgids, the
        TigerMarkView ProgID and capability registration, UserChoice, what AssocQueryString resolves
        for opening a .md file, the handlers SHAssocEnumHandlers offers (the Open with list), the
        TigerMarkView and legacy Add/Remove Programs entries, and the user PATH.

      shell.ps1 open <request.json> <result.json>
        Opens request.path with the Open with handler whose executable matches request.handler, the
        way Explorer's Open with menu does: IAssocHandler::Invoke on the file's shell data object.
#>
param(
    [Parameter(Mandatory)] [ValidateSet('probe', 'open')] [string] $Mode,
    [Parameter(Mandatory)] [string] $RequestPath,
    [Parameter(Mandatory)] [string] $ResultPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class TmvShell
{
    [ComImport, Guid("F04061AC-1659-4a3f-A954-775AA57FC083"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAssocHandler
    {
        void GetName([MarshalAs(UnmanagedType.LPWStr)] out string name);
        void GetUIName([MarshalAs(UnmanagedType.LPWStr)] out string name);
        void GetIconLocation([MarshalAs(UnmanagedType.LPWStr)] out string path, out int index);
        [PreserveSig] int IsRecommended();
        void MakeDefault([MarshalAs(UnmanagedType.LPWStr)] string description);
        void Invoke([MarshalAs(UnmanagedType.Interface)] object dataObject);
    }

    [ComImport, Guid("973810ae-9599-4b88-9e4d-6ee98c9552da"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IEnumAssocHandlers
    {
        [PreserveSig] int Next(uint count, [Out, MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 0)] IAssocHandler[] handlers, out uint fetched);
    }

    [ComImport, Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IShellItem
    {
        void BindToHandler(IntPtr bindContext, [In] ref Guid handler, [In] ref Guid interfaceId, out IntPtr result);
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern IEnumAssocHandlers SHAssocEnumHandlers(string extension, int filter);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SHCreateItemFromParsingName(string path, IntPtr bindContext, [In] ref Guid interfaceId, [MarshalAs(UnmanagedType.Interface)] out IShellItem item);

    [DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
    private static extern int AssocQueryString(int flags, int kind, string association, string extra, StringBuilder output, ref uint length);

    public class Handler
    {
        public string Name;
        public string UIName;
        public bool Recommended;
    }

    private static List<IAssocHandler> Enumerate(string extension)
    {
        var result = new List<IAssocHandler>();
        // ASSOC_FILTER_NONE: every handler Open with can offer, recommended or not.
        IEnumAssocHandlers enumerator = SHAssocEnumHandlers(extension, 0);
        var one = new IAssocHandler[1];
        uint fetched;
        while (enumerator.Next(1, one, out fetched) == 0 && fetched == 1)
        {
            result.Add(one[0]);
        }
        return result;
    }

    public static List<Handler> Handlers(string extension)
    {
        var list = new List<Handler>();
        foreach (IAssocHandler handler in Enumerate(extension))
        {
            var item = new Handler();
            handler.GetName(out item.Name);
            handler.GetUIName(out item.UIName);
            item.Recommended = handler.IsRecommended() == 0;
            list.Add(item);
        }
        return list;
    }

    public static string Query(string extension, int kind)
    {
        uint length = 2048;
        var output = new StringBuilder((int) length);
        int hr = AssocQueryString(0, kind, extension, "open", output, ref length);
        return hr == 0 ? output.ToString() : "hr:0x" + hr.ToString("X8");
    }

    public static string OpenWith(string path, string executableSuffix)
    {
        IAssocHandler chosen = null;
        foreach (IAssocHandler handler in Enumerate(System.IO.Path.GetExtension(path)))
        {
            string name;
            handler.GetName(out name);
            if (name != null && name.EndsWith(executableSuffix, StringComparison.OrdinalIgnoreCase)) { chosen = handler; break; }
        }
        if (chosen == null) { return "no Open with handler ends with " + executableSuffix; }

        Guid shellItemId = new Guid("43826d1e-e718-42ee-bc55-a1e261c37bfe");
        Guid dataObjectHandler = new Guid("B8C0BD9F-ED24-455c-83E6-D5390C4FE8C4");
        Guid dataObjectId = new Guid("0000010e-0000-0000-C000-000000000046");
        IShellItem item;
        SHCreateItemFromParsingName(path, IntPtr.Zero, ref shellItemId, out item);
        IntPtr pointer;
        item.BindToHandler(IntPtr.Zero, ref dataObjectHandler, ref dataObjectId, out pointer);
        object dataObject = Marshal.GetObjectForIUnknown(pointer);
        Marshal.Release(pointer);
        chosen.Invoke(dataObject);
        return null;
    }
}
'@

function Get-Value([string] $Key, [string] $Name) {
    $item = Get-ItemProperty -LiteralPath $Key -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    $property = $item.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    [string] $property.Value
}

function Get-ValueNames([string] $Key) {
    $item = Get-Item -LiteralPath $Key -ErrorAction SilentlyContinue
    if ($null -eq $item) { return @() }
    @($item.GetValueNames() | Where-Object { $_ })
}

$request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$classes = 'HKCU:\Software\Classes'
$uninstall = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'

if ($Mode -eq 'probe') {
    $extensions = [ordered]@{}
    foreach ($extension in '.md', '.markdown') {
        $extensions[$extension] = [ordered]@{
            classDefault = Get-Value "$classes\$extension" '(default)'
            openWithProgids = @(Get-ValueNames "$classes\$extension\OpenWithProgids")
            userChoice = Get-Value "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$extension\UserChoice" 'ProgId'
            capability = Get-Value 'HKCU:\Software\IT Tiger\TigerMarkView\Capabilities\FileAssociations' $extension
            # ASSOCSTR_COMMAND (1) and ASSOCSTR_PROGID (20): what opening such a file runs now.
            openCommand = [TmvShell]::Query($extension, 1)
            progId = [TmvShell]::Query($extension, 20)
            handlers = @([TmvShell]::Handlers($extension) | ForEach-Object { [ordered]@{ name = $_.Name; uiName = $_.UIName; recommended = $_.Recommended } })
        }
    }
    $result = [ordered]@{
        localAppData = $env:LOCALAPPDATA
        appData = $env:APPDATA
        extensions = $extensions
        progIdExists = Test-Path -LiteralPath "$classes\TigerMarkView.Markdown"
        progIdDescription = Get-Value "$classes\TigerMarkView.Markdown" '(default)'
        progIdCommand = Get-Value "$classes\TigerMarkView.Markdown\shell\open\command" '(default)'
        capabilitiesExists = Test-Path -LiteralPath 'HKCU:\Software\IT Tiger\TigerMarkView\Capabilities'
        registeredApplication = Get-Value 'HKCU:\Software\RegisteredApplications' 'TigerMarkView'
        registration = [ordered]@{
            exists = Test-Path -LiteralPath "$uninstall\ItTiger.TigerMarkView"
            displayName = Get-Value "$uninstall\ItTiger.TigerMarkView" 'DisplayName'
            displayVersion = Get-Value "$uninstall\ItTiger.TigerMarkView" 'DisplayVersion'
            publisher = Get-Value "$uninstall\ItTiger.TigerMarkView" 'Publisher'
            quietUninstall = Get-Value "$uninstall\ItTiger.TigerMarkView" 'QuietUninstallString'
        }
        legacyRegistration = Test-Path -LiteralPath "$uninstall\{E718860E-EDE4-4ACC-8235-BCF1DD40FC25}_is1"
        userPath = Get-Value 'HKCU:\Environment' 'Path'
    }
}
else {
    $failure = [TmvShell]::OpenWith([string] $request.path, [string] $request.handler)
    # The shell starts the handler asynchronously; stay alive while it does.
    Start-Sleep -Seconds 5
    $result = [ordered]@{ invoked = ($null -eq $failure); failure = $failure }
}

$json = $result | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($ResultPath, $json, (New-Object Text.UTF8Encoding $false))
exit 0
