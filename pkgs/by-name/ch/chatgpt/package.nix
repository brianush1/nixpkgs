{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  unzip,
  dpkg,
  autoPatchelfHook,
  makeShellWrapper,
  nodejs,
  wrapGAppsHook3,
  alsa-lib,
  atk,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  git,
  glib,
  glibc,
  gtk3,
  libdrm,
  libgbm,
  libglvnd,
  libnotify,
  libusb1,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxrandr,
  nspr,
  nss,
  pango,
  systemd,
  xdg-utils,
}:

let
  source =
    (import ./source.nix).${stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${stdenv.hostPlatform.system}");

  pname = "chatgpt";
  passthru.updateScript = ./update.sh;

  meta = {
    description = "Desktop application for ChatGPT";
    homepage = "https://chatgpt.com/download/";
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [ wattmto ];
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };

  darwin = stdenvNoCC.mkDerivation {
    inherit pname passthru;
    inherit (source) version;

    src = fetchurl {
      inherit (source) url hash;
    };

    strictDeps = true;
    __structuredAttrs = true;

    nativeBuildInputs = [ unzip ];

    sourceRoot = ".";

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/Applications" "$out/bin"
      cp -a ChatGPT.app "$out/Applications"
      ln -s "$out/Applications/ChatGPT.app/Contents/MacOS/ChatGPT" "$out/bin/ChatGPT"

      runHook postInstall
    '';

    meta = meta // {
      changelog = "https://help.openai.com/en/articles/9703738-macos-app-release-notes";
      mainProgram = "ChatGPT";
    };
  };

  linux = stdenv.mkDerivation {
    inherit pname passthru;
    inherit (source) version;

    src = fetchurl {
      inherit (source) url hash name;
    };

    strictDeps = true;
    __structuredAttrs = true;

    nativeBuildInputs = [
      autoPatchelfHook
      dpkg
      makeShellWrapper
      nodejs
      wrapGAppsHook3
    ];

    buildInputs = [
      alsa-lib
      atk
      at-spi2-atk
      at-spi2-core
      cairo
      cups
      dbus
      expat
      gdk-pixbuf
      glib
      gtk3
      libdrm
      libgbm
      libnotify
      libusb1
      libx11
      libxcb
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxkbcommon
      libxrandr
      nspr
      nss
      pango
      stdenv.cc.cc
      systemd
    ];

    runtimeDependencies = [ libglvnd ];

    # These are optional upstream fallbacks. The Qt shims are loaded only when
    # the matching Qt version is available, and the musl prebuilds are unused
    # by this glibc package.
    autoPatchelfIgnoreMissingDeps = [
      "libQt5Core.so.5"
      "libQt5Gui.so.5"
      "libQt5Widgets.so.5"
      "libQt6Core.so.6"
      "libQt6Gui.so.6"
      "libQt6Widgets.so.6"
      "libc.musl-*.so.1"
    ];

    unpackPhase = ''
      runHook preUnpack

      dpkg-deb -x "$src" .

      runHook postUnpack
    '';

    sourceRoot = ".";
    dontWrapGApps = true;

    # Avoid detect-libc's process.report fallback, which crashes Electron's
    # repository watcher on NixOS when /usr/bin/ldd does not exist.
    postPatch = ''
      node ${./patch-ldd-path.cjs} \
        "$PWD/usr/lib/chatgpt/resources/app.asar" \
        "${lib.getBin glibc}/bin/ldd"
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -r usr/* "$out/"
      rm "$out/bin/chatgpt"
      makeShellWrapper "$out/lib/chatgpt/ChatGPT" "$out/bin/chatgpt" \
        "''${gappsWrapperArgs[@]}" \
        --prefix PATH : "${
          lib.makeBinPath [
            git
            xdg-utils
          ]
        }" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libglvnd ]}" \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

      runHook postInstall
    '';

    meta = meta // {
      mainProgram = "chatgpt";
    };
  };
in
if stdenv.hostPlatform.isDarwin then darwin else linux
