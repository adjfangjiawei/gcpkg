/* Disk-information query stack smoke test.
 *
 * The headers come from three independent gcpkg ports; clangd resolves all of
 * them through the merged compile_commands.json in this project directory.
 */
#include <stdio.h>
#include <nvme/tree.h>     /* libnvme: nvme_scan(), nvme_ctrl ... */
#include <atasmart.h>      /* libatasmart: SkDisk, sk_disk_smart_read_data() */
#include <pci.h>           /* pciutils: struct pci_access, pci_alloc() ... */

int main(void) {
    puts("diskinfo-smoke: NVMe / ATA SMART / PCI headers resolved");
    return 0;
}
