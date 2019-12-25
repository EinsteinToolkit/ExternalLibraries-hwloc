#include <hwloc.h>

#include <cctk.h>

int hwloc_version(void) {
  const char *library_version = HWLOC_VERSION;
  unsigned buildtime_api_version = HWLOC_API_VERSION;
  unsigned runtime_api_version = hwloc_get_api_version();
  // TODO: Check only major version number?
  if (runtime_api_version != buildtime_api_version)
    CCTK_VERROR("library version %s, build-time API version 0x%x, run-time API "
                "version 0x%x",
                library_version, buildtime_api_version, runtime_api_version);
  CCTK_VINFO("library version %s, API version 0x%x", library_version,
             buildtime_api_version);
  return 0;
}
