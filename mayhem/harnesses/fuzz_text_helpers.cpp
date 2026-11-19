// Fuzz the string helpers that handle attacker-influenced text:
//  - extractWdgErrorReason (WdgResponse.cpp): the WDGoWars HTTP response body
//  - marauder::parseMacAddress (MarauderMacAddress.cpp): MAC text from CLI/files
//  - CensorText::{looksLikeMac,name,mac,identifier} (CensorText.cpp): SSIDs,
//    device names and IDs heard over the air, censored in place for display
//  - fitDisplayLine (DisplayLine.cpp): any of the above clipped to a screen line
// Byte 0 sizes the output buffers; the rest is a NUL-terminated heap copy.
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <vector>

#include "CensorText.h"
#include "DisplayLine.h"
#include "MarauderMacAddress.h"
#include "WdgResponse.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  if (size < 1) return -1;
  const size_t out_size = data[0] % 80;  // 0..79, includes the 0/1 edge cases
  std::vector<char> text(data + 1, data + size);
  text.push_back('\0');

  std::vector<char> out(out_size ? out_size : 1);
  extractWdgErrorReason(text.data(), out_size ? out.data() : nullptr, out_size);

  uint8_t mac[marauder::kMacAddressSize];
  if (marauder::parseMacAddress(text.data(), mac)) {
    char formatted[marauder::kMacAddressTextLength + 1];
    marauder::formatMacAddress(mac, formatted);
  }

  CensorText::looksLikeMac(text.data());
  std::vector<char> scratch(text);
  CensorText::name(scratch.data());
  scratch = text;
  CensorText::mac(scratch.data());
  scratch = text;
  CensorText::identifier(scratch.data());

  if (out_size) fitDisplayLine(out.data(), out_size, text.data());
  return 0;
}
