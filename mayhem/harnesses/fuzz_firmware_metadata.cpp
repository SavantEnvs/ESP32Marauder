// Fuzz the firmware-image metadata scanner (FirmwareMetadata.cpp) used by the
// SD-card updater (SDInterface.cpp) on an untrusted update.bin: every byte of
// the image is pushed into a MetadataScanner, and a found block is validated
// and compared against this build's metadata, as the updater does.
#include <stddef.h>
#include <stdint.h>

#include "FirmwareMetadata.h"

using namespace MarauderFirmware;

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  MetadataScanner scanner;
  for (size_t i = 0; i < size; ++i) {
    if (scanner.push(data[i])) break;
  }
  if (scanner.found()) {
    const Metadata& metadata = scanner.metadata();
    if (validMetadata(metadata)) metadataMatches(metadata, currentMetadata());
  }
  return 0;
}
