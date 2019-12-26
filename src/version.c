#include <hwloc.h>

#include <cctk.h>

int hwloc_version(void) {
  const char *library_version =
  // HWLOC_VERSION appears first in hwloc 2.1, before that one has to consult
  // the output of hwloc-info --version or pkgconfig
#if defined(HWLOC_VERSION) // modern hwloc
  HWLOC_VERSION;
#elif defined(HWLOC_VERSION_BUILD) // bundled copy
  HWLOC_VERSION_BUILD;
#elif defined(HWLOC_VERSION_PKGCONFIG)  // found via pkgconfig
  HWLOC_VERSION_PKGCONFIG;
#elif defined(HWLOC_VERSION_HWLOCINFO) // found hwloc-info
  HWLOC_VERSION_HWLOCINFO;
#else
  "unknown";
#endif
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
