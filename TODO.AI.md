done | fresh-install-baseline | Run syntax/baseline checks, create fresh Incus containers, push current tree
done | clean-installs | Run clean installs in fresh Debian 12, AlmaLinux 9, and Fedora 42 containers
done | install-failure-fixes | Eliminate remaining installer/runtime warning bugs found in clean runs (Asternic, Asteridex, chrony container noise)
done | script-validation | Validate bundled test scripts and management scripts on successful fresh installs
done | idempotency-reruns | Re-run installer on successful fresh installs and fix any idempotency regressions
in-progress | matrix-image-check | Verify Incus images for Debian 11/13, AlmaLinux 8/10, and Ubuntu 22.04/24.04 and select exact aliases
pending | matrix-clean-installs | Launch fresh matrix containers and run installer on Debian 11/13, AlmaLinux 8/10, and Ubuntu 22.04/24.04
pending | matrix-comprehensive-tests | Run comprehensive suite in each successful new matrix container and fix any failures
pending | matrix-cleanup | Delete temporary matrix validation containers after results are confirmed
