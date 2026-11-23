{
  pkgs,
  lib,
  ...
}: let
  uplink = "eno1";
  bridgeMac = "bc:fc:e7:8c:80:eb";

  networks = {
    default = {
      file = ./networks/default.xml;
      autostart = false;
    };
    isolated-network = {
      file = ./networks/isolated-network.xml;
      autostart = true;
    };
  };
  pools.default = {
    file = ./pools/default.xml;
    autostart = true;
  };
  domains = {
    nixos-26-05 = ./domains/nixos-26.05.xml;
    win11 = ./domains/win11.xml;
  };

  virsh = "${pkgs.libvirt}/bin/virsh -c qemu:///system";
  grep = "${pkgs.gnugrep}/bin/grep";
  flag = autostart:
    if autostart
    then ""
    else "--disable";

  defineNetworks = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: n: ''
      ${virsh} net-define ${n.file}
      ${virsh} net-autostart ${flag n.autostart} ${name}
      ${lib.optionalString n.autostart "${virsh} net-info ${name} | ${grep} -q 'Active: *no' && ${virsh} net-start ${name}"}
    '')
    networks);
  definePools = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: p: ''
      ${virsh} pool-define ${p.file}
      ${virsh} pool-autostart ${flag p.autostart} ${name}
      ${lib.optionalString p.autostart "${virsh} pool-info ${name} | ${grep} -q 'State: *inactive' && ${virsh} pool-start ${name}"}
    '')
    pools);
  defineDomains = lib.concatStringsSep "\n" (lib.mapAttrsToList (_: file: "${virsh} define ${file}") domains);
in {
  # Bridge br0 on top of the uplink: host and bridged VMs get their own DHCP
  # leases. br0 clones the uplink's MAC so the host keeps its current IP address.
  networking.networkmanager.ensureProfiles.profiles = {
    br0 = {
      connection = {
        id = "br0";
        uuid = "838468b3-7f13-470f-857a-504a7c04f650";
        type = "bridge";
        interface-name = "br0";
        autoconnect-priority = 100;
      };
      bridge = {
        stp = "false";
      };
      ethernet.cloned-mac-address = bridgeMac;
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
    br0-uplink = {
      connection = {
        id = "br0-${uplink}";
        uuid = "c29d1324-a6a5-4e6c-b40b-3dd9b7fbb694";
        type = "ethernet";
        interface-name = uplink;
        master = "br0";
        slave-type = "bridge";
        autoconnect-priority = 100;
      };
    };
  };

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
    };
  };

  programs.virt-manager.enable = true;

  systemd.tmpfiles.rules = ["d /var/lib/libvirt/images 0711 root root -"];

  systemd.services.libvirt-definitions = {
    description = "Define libvirt networks, storage pools and domains";
    wantedBy = ["multi-user.target"];
    after = ["libvirtd.service"];
    requires = ["libvirtd.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${defineNetworks}
      ${definePools}
      ${defineDomains}
    '';
  };
}
