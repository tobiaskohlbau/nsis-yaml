{ pkgs ? import <nixpkgs> { }, }:
pkgs.mkShell {
  buildInputs = with pkgs; [
    nixfmt-rfc-style
    zigpkgs.master
    lldb
    zls
  ];

  shellHook = ''
  '';
}
