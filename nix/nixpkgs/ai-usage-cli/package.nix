{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  python3,
  libsecret,
  nix-update-script,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ai-usage-cli";
  version = "3.3.1";

  src = fetchFromGitHub {
    owner = "Muddyblack";
    repo = "ai-usage-widget";
    tag = "v${finalAttrs.version}";
    hash = "sha256-RT/x9eEBrnbOpa6ghyDrdntsXrKl4fslxGJahn82CrM=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest=$out/share/ai-usage-widget
    mkdir -p "$dest" "$out/bin"
    cp -r backend "$dest/backend"
    find "$dest" \( -name '__pycache__' -o -name '*.pyc' \) -prune -exec rm -rf {} +

    substituteInPlace "$dest/backend/sh/python-interp.sh" \
      --replace-fail 'PY_DEFAULT="python3"' \
                     'PY_DEFAULT="${lib.getExe python3}"'
    substituteInPlace "$dest/backend/aiusage/providers/antigravity_remote.py" \
      --replace-fail 'SECRET_TOOL = "secret-tool"' \
                     'SECRET_TOOL = "${lib.getExe' libsecret "secret-tool"}"'

    # The launchers resolve symlinks to find the aiusage package beside them.
    ln -s "$dest/backend/sh/ai-usage-cli" "$out/bin/ai-usage-cli"
    ln -s "$dest/backend/sh/get-ai-usage" "$out/bin/get-ai-usage"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/ai-usage-cli --help > /dev/null
    runHook postInstallCheck
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Terminal frontend of the AI usage widget: provider limits as a table or a status-bar line";
    homepage = "https://github.com/Muddyblack/ai-usage-widget";
    changelog = "https://github.com/Muddyblack/ai-usage-widget/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ai-usage-cli";
    maintainers = [ ];
  };
})
