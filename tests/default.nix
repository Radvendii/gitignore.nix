{ pkgs ? import <nixpkgs> {}, lib ? pkgs.lib }:

let
  testdata = import ./testdata.nix { inherit pkgs; };
  runner = import ./runner.nix { inherit pkgs; };
  gitignoreNix = (import ../. { inherit lib; });
  inherit (gitignoreNix) gitignoreSource;
in
{
  plain = runner.makeTest { name = "plain"; rootDir = testdata.sourceUnfiltered + "/test-tree"; };
  nested = runner.makeTest { name = "nested"; rootDir = testdata.sourceUnfilteredRecursive + "/test-tree"; };

  plain-with-testdata-dir = runner.makeTest { name = "plain"; rootDir = testdata.sourceUnfiltered; };
  nested-with-testdata-dir = runner.makeTest { name = "nested"; rootDir = testdata.sourceUnfilteredRecursive; };

  plain-with-testdata-subdir = runner.makeTest { name = "plain"; rootDir = testdata.sourceUnfiltered; subpath = "test-tree"; };
  nested-with-testdata-subdir = runner.makeTest { name = "nested"; rootDir = testdata.sourceUnfilteredRecursive; subpath = "test-tree"; };

  subdir-1 = runner.makeTest { name = "subdir-1"; rootDir = testdata.sourceUnfiltered + "/test-tree"; subpath = "1-simpl"; };
  subdir-1x = runner.makeTest { name = "subdir-1x"; rootDir = testdata.sourceUnfiltered + "/test-tree"; subpath = "1-xxxxx"; };
  subdir-2 = runner.makeTest { name = "subdir-2"; rootDir = testdata.sourceUnfiltered + "/test-tree"; subpath = "2-negation"; };
  subdir-3 = runner.makeTest { name = "subdir-3"; rootDir = testdata.sourceUnfiltered + "/test-tree"; subpath = "3-wildcards"; };
  subdir-4 = runner.makeTest { name = "subdir-4"; rootDir = testdata.sourceUnfiltered + "/test-tree"; subpath = "4-escapes"; };
  subdir-9 = runner.makeTest { name = "subdir-9"; rootDir = testdata.sourceUnfiltered + "/test-tree"; subpath = "9-expected"; };
  subdir-10 = runner.makeTest { name = "subdir-10"; rootDir = testdata.sourceUnfiltered + "/test-tree"; subpath = "10-subdir-ignoring-itself"; };

  # https://github.com/hercules-ci/gitignore.nix/pull/71
  regression-config-with-store-path =
    let
      excludesfile = pkgs.writeText "excludesfile" "";
      gitconfig = pkgs.writeText "gitconfig" ''
        [core]
            excludesfile = ${excludesfile}
      '';
    in
    pkgs.stdenv.mkDerivation {
      name = "config-with-store-path";
      src = testdata.sourceUnfiltered + "/test-tree";
      buildInputs = [ pkgs.nix ];
      NIX_PATH="nixpkgs=${pkgs.path}";
      buildPhase = ''
        HOME=/build/HOME
        mkdir -p $HOME

        # it must be a symlink to the nix store.
        # that way builtins.readFile adds in the relevant context
        ln -s ${gitconfig} $HOME/.gitconfig

        export NIX_LOG_DIR=$TMPDIR
        export NIX_STATE_DIR=$TMPDIR

        echo ---------------

        # outside of a nix-build, the context of this would be non-empty (replaceing the ''${} with ())
        # inside the nix build, it's empty.
        # Arghhhh

        nix-instantiate --eval --expr --strict --json --readonly-mode --option sandbox false \
            'let pkgs = import <nixpkgs> {}; in builtins.getContext (builtins.readFile ${pkgs.writeText "foo" (toString pkgs.hello)})'

        echo ---------------

        if nix-instantiate --eval --expr \
            --readonly-mode --option sandbox false \
            '((import ${gitignoreSource ../.} {}).gitignoreSource ./.).outPath'
        then touch $out
        else
          echo
          echo "Failed to run with a global excludes file from the nix store."
          echo "This may be because the store path gets misinterpreted as a string context."
          echo "See https://github.com/hercules-ci/gitignore.nix/pull/71"
          exit 1
        fi
      '';
      preInstall = "";
      installPhase = ":";
    };

  # Make sure the files aren't added to the store before filtering.
  shortcircuit = runner.makeTest {
    name = "nested";
    rootDir = testdata.sourceUnfilteredRecursive + "/test-tree";
    preCheck = ''
      # Instead of a file, create a fifo so that the filter would error out if it tries to add it to the store.
      rm 1-simpl/1
      mkfifo 1-simpl/1
    '';
  };

  unit-tests =
    let inherit (gitignoreNix) gitignoreFilterWith gitignoreSourceWith;
        example = gitignoreFilterWith { basePath = ./.; extraRules = ''
          *.foo
          !*.bar
        ''; };
        shortcircuit = gitignoreSourceWith {
          path = {
            inherit (lib.cleanSource ./.) _isLibCleanSourceWith filter name;
            outPath = throw "do not use outPath";
            origSrc = ./.;
          };
        };
    in

    # Test that extraRules works:
    assert example ./x.foo "regular" == false;
    assert example ./x.bar "regular" == true;
    assert example ./x.qux "regular" == true;

    # Make sure outPath is not used. (It's not about the store path)
    assert lib.hasPrefix builtins.storeDir "${shortcircuit}";

    # End of test. (a drv to show a buildable attr when successful)
    pkgs.emptyFile or null;
}
