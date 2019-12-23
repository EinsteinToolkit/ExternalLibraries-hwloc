#include <hwloc.h>

#include <cctk.h>

int hwloc_version(void) {
  unsigned buildtime_api_version = HWLOC_API_VERSION;
  unsigned runtime_api_version = hwloc_get_api_version();
  if (runtime_api_version != buildtime_api_version)
    CCTK_VERROR("build-time API version: 0x%x, run-time API version: 0x%x",
                buildtime_api_version, runtime_api_version);
  CCTK_VINFO("API version 0x%x", buildtime_api_versionx);
  return 0;
}
