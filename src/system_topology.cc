#include <cctk.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <list>
#include <map>
#include <string>
#include <vector>

#ifdef HAVE_CAPABILITY_MPI
#  include <mpi.h>
#endif

#ifdef _OPENMP
#  include <omp.h>
#else
namespace {
  int omp_get_max_threads() { return 1; }
  int omp_get_num_threads() { return 1; }
  int omp_get_thread_num() { return 0; }
}
#endif

#include <hwloc.h>

#ifdef __bgq__
#  include <spi/include/kernel/location.h>
#endif

using namespace std;



namespace {
  int divup(int a, int b)
  {
    assert(a>=0);
    assert(b>0);
    return (a+b-1)/b;
  }
  
  bool is_pow2(int a)
  {
    if (a<=0) return false;
    while (a!=1) {
      if (a%2) return false;
      a/=2;
    }
    return true;
  }
}



namespace {
  
  struct mpi_host_mapping_t {
    int mpi_num_procs, mpi_proc_num;
    int mpi_num_hosts, mpi_host_num;
    int mpi_num_procs_on_host, mpi_proc_num_on_host;
    
    void load();
  };
  
#ifdef HAVE_CAPABILITY_MPI
  
  void mpi_host_mapping_t::load()
  {
    CCTK_INFO("MPI process-to-host mapping:");
    
    MPI_Comm comm = MPI_COMM_WORLD;
    int const root = 0;
    
    MPI_Comm_size(comm, &mpi_num_procs);
    MPI_Comm_rank(comm, &mpi_proc_num);
    printf("This is MPI process %d of %d\n", mpi_proc_num, mpi_num_procs);
    
    char procname[MPI_MAX_PROCESSOR_NAME];
    int procnamelen;
    MPI_Get_processor_name(procname, &procnamelen);
    vector<char> procnames;
    if (mpi_proc_num == root) {
      procnames.resize(MPI_MAX_PROCESSOR_NAME * mpi_num_procs);
    }
    MPI_Gather(procname, MPI_MAX_PROCESSOR_NAME, MPI_CHAR,
               &procnames[0], MPI_MAX_PROCESSOR_NAME, MPI_CHAR,
               root, comm);
    vector<int> host_byproc;
    map<int, list<int> > host2procs1;
    if (mpi_proc_num == root) {
      map<string, int> hostname2host;
      vector<string> hostnames;
      hostnames.reserve(mpi_num_procs);
      host_byproc.resize(mpi_num_procs);
      mpi_num_hosts = 0;
      for (int proc=0; proc<mpi_num_procs; ++proc) {
        string hostname(&procnames[MPI_MAX_PROCESSOR_NAME * proc]);
        if (hostname2host.count(hostname) == 0) {
          hostname2host[hostname] = mpi_num_hosts;
          hostnames.push_back(hostname);
          ++mpi_num_hosts;
        }
        int host = hostname2host[hostname];
        host_byproc[proc] = host;
        host2procs1[host].push_back(proc);
      }
      printf("MPI hosts:\n");
      for (int host=0; host<mpi_num_hosts; ++host) {
        printf("  %d: %s\n", host, hostnames[host].c_str());
      }
    }
    MPI_Bcast(&mpi_num_hosts, 1, MPI_INT, root, comm);
    MPI_Scatter(&host_byproc[0], 1, MPI_INT,
                &mpi_host_num, 1, MPI_INT,
                root, comm);
    printf("This MPI process runs on host %d of %d\n",
           mpi_host_num, mpi_num_hosts);
    
    vector<int> num_procs_on_host_byproc;
    vector<int> proc_num_on_host_byproc;
    if (mpi_proc_num == root) {
      vector<vector<int> > host2procs(mpi_num_hosts);
      vector<int> num_procs_on_host_byhost(mpi_num_hosts);
      num_procs_on_host_byproc.resize(mpi_num_procs);
      proc_num_on_host_byproc.resize(mpi_num_procs);
      for (int host=0; host<mpi_num_hosts; ++host) {
        list<int> const& host_procs1 = host2procs1[host];
        vector<int>& host_procs = host2procs[host];
        host_procs.reserve(host_procs1.size());
        for (list<int>::const_iterator
               iproc = host_procs1.begin(); iproc != host_procs1.end(); ++iproc)
        {
          host_procs.push_back(*iproc);
        }
        sort(host_procs.begin(), host_procs.end());
        int num_procs_on_host = host_procs.size();
        num_procs_on_host_byhost[host] = num_procs_on_host;
        for (int proc_num_on_host=0;
             proc_num_on_host<num_procs_on_host;
             ++proc_num_on_host)
        {
          int proc = host_procs[proc_num_on_host];
          num_procs_on_host_byproc[proc] = num_procs_on_host;
          proc_num_on_host_byproc[proc] = proc_num_on_host;
        }
      }
    }
    MPI_Scatter(&num_procs_on_host_byproc[0], 1, MPI_INT,
                &mpi_num_procs_on_host, 1, MPI_INT,
                root, comm);
    MPI_Scatter(&proc_num_on_host_byproc[0], 1, MPI_INT,
                &mpi_proc_num_on_host, 1, MPI_INT,
                root, comm);
    printf("On this host, this is MPI process %d of %d\n",
           mpi_proc_num_on_host, mpi_num_procs_on_host);
  }
  
#else
  
  void mpi_host_mapping_t::load()
  {
    mpi_num_procs         = 1;
    mpi_proc_num          = 0;
    mpi_num_hosts         = 1;
    mpi_host_num          = 0;
    mpi_num_procs_on_host = 1;
    mpi_proc_num_on_host  = 0;
  }
  
#endif
  
}



// Inspired by code in hwloc's documentation

namespace {
  
#define OUTPUT_SUPPORT(FIELD)                                           \
  printf("  %-41s: %s\n", #FIELD, topology_support->FIELD ? "yes" : "no")
  
  void output_support(hwloc_topology_t topology)
  {
    CCTK_INFO("Topology support:");
    hwloc_topology_support const* topology_support =
      hwloc_topology_get_support(topology);
    printf("Discovery support:\n");
    OUTPUT_SUPPORT(discovery->pu);
    printf("CPU binding support:\n");
    OUTPUT_SUPPORT(cpubind->set_thisproc_cpubind            );
    OUTPUT_SUPPORT(cpubind->get_thisproc_cpubind            );
    OUTPUT_SUPPORT(cpubind->set_proc_cpubind                );
    OUTPUT_SUPPORT(cpubind->get_proc_cpubind                );
    OUTPUT_SUPPORT(cpubind->set_thisthread_cpubind          );
    OUTPUT_SUPPORT(cpubind->get_thisthread_cpubind          );
    OUTPUT_SUPPORT(cpubind->set_thread_cpubind              );
    OUTPUT_SUPPORT(cpubind->get_thread_cpubind              );
    OUTPUT_SUPPORT(cpubind->get_thisproc_last_cpu_location  );
    OUTPUT_SUPPORT(cpubind->get_proc_last_cpu_location      );
    OUTPUT_SUPPORT(cpubind->get_thisthread_last_cpu_location);
    printf("Memory binding support:\n");
    OUTPUT_SUPPORT(membind->set_thisproc_membind  );
    OUTPUT_SUPPORT(membind->get_thisproc_membind  );
    OUTPUT_SUPPORT(membind->set_proc_membind      );
    OUTPUT_SUPPORT(membind->get_proc_membind      );
    OUTPUT_SUPPORT(membind->set_thisthread_membind);
    OUTPUT_SUPPORT(membind->get_thisthread_membind);
    OUTPUT_SUPPORT(membind->set_area_membind      );
    OUTPUT_SUPPORT(membind->get_area_membind      );
    OUTPUT_SUPPORT(membind->alloc_membind         );
    OUTPUT_SUPPORT(membind->firsttouch_membind    );
    OUTPUT_SUPPORT(membind->bind_membind          );
    OUTPUT_SUPPORT(membind->interleave_membind    );
    OUTPUT_SUPPORT(membind->replicate_membind     );
    OUTPUT_SUPPORT(membind->nexttouch_membind     );
    OUTPUT_SUPPORT(membind->migrate_membind       );
  }
  
  
  
  void output_object(hwloc_topology_t topology,
                     hwloc_obj_t obj,
                     int depth)
  {
    char type_buf[1000], attr_buf[1000];
    hwloc_obj_type_snprintf(type_buf, sizeof type_buf, obj, 1);
    hwloc_obj_attr_snprintf(attr_buf, sizeof attr_buf, obj, ", ", 1);
    printf("%*s%s L#%d: (P#%d%s%s)\n", 2*depth, "",
           type_buf, obj->logical_index,
           obj->os_index, strlen(attr_buf)==0 ? "" : ", ", attr_buf);
    
    for (unsigned i=0; i<obj->arity; ++i) {
      // TODO: output index (physical, logical?)
      output_object(topology, obj->children[i], depth+1);
    }
  }
  
  void output_objects(hwloc_topology_t topology)
  {
    CCTK_INFO("Hardware objects in this node:");
    output_object(topology, hwloc_get_root_obj(topology), 0);
  }
  
  
  
  void output_bindings(hwloc_topology_t topology)
  {
    hwloc_topology_support const* topology_support =
      hwloc_topology_get_support(topology);
    if (not topology_support->cpubind->get_thisthread_cpubind) {
      CCTK_INFO("Cannot determine thread CPU bindings");
      return;
    }
    
    CCTK_INFO("Thread CPU bindings:");
#pragma omp parallel
    {
      int const num_threads = omp_get_num_threads();
      for (int thread=0; thread<num_threads; ++thread) {
        if (thread == omp_get_thread_num()) {
          int ierr;
          hwloc_cpuset_t cpuset = hwloc_bitmap_alloc();
          if (not cpuset) {
            CCTK_VWarn(CCTK_WARN_ALERT, __LINE__, __FILE__, CCTK_THORNSTRING,
                       "Could not allocate bitmap for CPU bindings");
            goto next;
          }
          ierr = hwloc_get_cpubind(topology, cpuset, HWLOC_CPUBIND_THREAD);
          if (ierr) {
            CCTK_VWarn(CCTK_WARN_ALERT, __LINE__, __FILE__, CCTK_THORNSTRING,
                       "Could not obtain CPU binding for thread %d", thread);
            goto next_free;
          }
          char cpuset_buf[1000];
          hwloc_bitmap_list_snprintf(cpuset_buf, sizeof cpuset_buf, cpuset);
          printf("OMP thread %d: PU set P#{%s}\n", thread, cpuset_buf);
        next_free:
          hwloc_bitmap_free(cpuset);
        next:;
        }
#pragma omp barrier
      }
    }
  }
  
  
  
  void set_bindings(hwloc_topology_t topology,
                    mpi_host_mapping_t const& host_mapping)
  {
    hwloc_topology_support const* topology_support =
      hwloc_topology_get_support(topology);
    if (not topology_support->cpubind->set_thisthread_cpubind) {
      CCTK_INFO("Cannot set thread CPU bindings");
      return;
    }
    
    // TODO: use hwloc_distribute instead
    CCTK_INFO("Setting thread CPU bindings:");
#pragma omp parallel
    {
      // All quantities are per host
      int const pu_depth =
        hwloc_get_type_or_below_depth(topology, HWLOC_OBJ_PU);
      assert(pu_depth>=0);
      int const num_pus = hwloc_get_nbobjs_by_depth(topology, pu_depth);
      assert(num_pus>0);
      int const num_threads_in_proc = omp_get_num_threads();
      int const num_procs = host_mapping.mpi_num_procs_on_host;
      int const num_threads = num_threads_in_proc * num_procs;
      int const proc_num =  host_mapping.mpi_proc_num_on_host;
      int const thread_offset = num_threads_in_proc * proc_num;
      // Bind thread to exactly one PU
      for (int thread_num_in_proc=0;
           thread_num_in_proc<num_threads_in_proc;
           ++thread_num_in_proc)
      {
        if (thread_num_in_proc == omp_get_thread_num()) {
          int const thread_num = thread_offset + thread_num_in_proc;
          int const pu_num = thread_num * num_pus / num_threads;
          hwloc_obj_t pu_obj =
            hwloc_get_obj_by_depth(topology, pu_depth, pu_num);
          CCTK_VInfo(CCTK_THORNSTRING,
                     "Binding thread %d of process %d (thread %d on host %d) to PU %d (P#%d)",
                     thread_num_in_proc, host_mapping.mpi_proc_num,
                     thread_num, host_mapping.mpi_host_num,
                     pu_num, pu_obj->os_index);
          // hwloc_cpuset_t cpuset = hwloc_bitmap_dup(pu_obj->cpuset);
          hwloc_cpuset_t cpuset = pu_obj->cpuset;
          int ierr;
          ierr = hwloc_set_cpubind(topology, cpuset,
                                   HWLOC_CPUBIND_THREAD | HWLOC_CPUBIND_STRICT);
          if (ierr) {
            ierr = hwloc_set_cpubind(topology, cpuset, HWLOC_CPUBIND_THREAD);
          }
          if (ierr) {
            CCTK_VWarn(CCTK_WARN_ALERT, __LINE__, __FILE__, CCTK_THORNSTRING,
                      "Could not set CPU binding for thread %d",
                      thread_num_in_proc);
          }
          // hwloc_bitmap_free(cpuset);
        }
#pragma omp barrier
      }
    }
  }
  
}



namespace {
  
  struct node_topology_info_t {
    int num_smt_threads;        // threads per core
    struct cache_info_t {
      int linesize;             // data cache line size in bytes
      int stride;               // data cache stride in bytes
    };
    vector<cache_info_t> cache_info;
    
    void load(hwloc_topology_t const& topology,
              mpi_host_mapping_t const& mpi_host_mapping);
  };
  
  node_topology_info_t* node_topology_info = NULL;
  
  void node_topology_info_t::load(hwloc_topology_t const& topology,
                                  mpi_host_mapping_t const& mpi_host_mapping)
  {
    int const core_depth =
      hwloc_get_type_or_below_depth(topology, HWLOC_OBJ_CORE);
    assert(core_depth>=0);
    int const num_cores = hwloc_get_nbobjs_by_depth(topology, core_depth);
    assert(num_cores>0);
    int const pu_depth =
      hwloc_get_type_or_below_depth(topology, HWLOC_OBJ_PU);
    assert(pu_depth>=0);
    int const num_pus = hwloc_get_nbobjs_by_depth(topology, pu_depth);
    assert(num_pus>0);
    int const smt_multiplier = num_pus / num_cores;
    printf("There are %d PUs per core (aka hardware SMT threads)\n",
           smt_multiplier);
    int const num_cores_in_process =
      divup(num_cores, mpi_host_mapping.mpi_num_procs_on_host);
    num_smt_threads = divup(omp_get_max_threads(), num_cores_in_process);
    printf("There are %d threads per core (aka SMT threads used)\n",
           num_smt_threads);
    if (num_smt_threads > smt_multiplier) {
      printf("WARNING: This is larger than the number of hardware SMT threads\n");
    }
    assert(num_smt_threads > 0);
    
    assert(cache_info.empty());
    for (int cache_level = 1; true; ++cache_level) {
      int const cache_depth =
        hwloc_get_cache_type_depth(topology, cache_level, HWLOC_OBJ_CACHE_DATA);
      if (cache_depth<0) break;
      int const cache_num = 0;    // just look at first cache
      hwloc_obj_t const cache_obj =
        hwloc_get_obj_by_depth(topology, cache_depth, cache_num);
      assert(cache_obj->type == HWLOC_OBJ_CACHE);
      hwloc_obj_attr_u::hwloc_cache_attr_s const& cache_attr =
        cache_obj->attr->cache;
      char const* const cache_type_str =
        cache_attr.type == HWLOC_OBJ_CACHE_UNIFIED     ? "unified" :
        cache_attr.type == HWLOC_OBJ_CACHE_DATA        ? "data" :
        cache_attr.type == HWLOC_OBJ_CACHE_INSTRUCTION ? "instruction" :
        "UNKNOWN";
      int const cache_stride =
        (cache_attr.associativity == 0 ?
         0 :
         cache_attr.size / cache_attr.associativity);
      printf("Cache %s has type \"%s\" depth %d\n"
             "   size %td linesize %d associativity %d stride %d\n",
             cache_obj->name ? cache_obj->name : "(unknown name)",
             cache_type_str,
             cache_attr.depth,
             (ptrdiff_t)cache_attr.size,
             cache_attr.linesize,
             cache_attr.associativity,
             cache_stride);
      assert(cache_attr.linesize > 0);
      assert(is_pow2(cache_attr.linesize));
      assert(cache_stride >= 0);
      // Cache strides may not be powers of two
      // assert(cache_stride==0 or is_pow2(cache_stride));
      cache_info_t new_cache_info;
      new_cache_info.linesize = cache_attr.linesize;
      new_cache_info.stride   = cache_stride;
      cache_info.push_back(new_cache_info);
    }
  }
  
}



extern "C"
CCTK_INT hwloc_GetNumSMTThreads()
{
  return node_topology_info->num_smt_threads;
}

extern "C"
CCTK_INT hwloc_GetCacheInfo(CCTK_INT* restrict const linesizes,
                            CCTK_INT* restrict const strides,
                            CCTK_INT const max_num_cache_levels)
{
  int const num_levels = min(int(max_num_cache_levels),
                             int(node_topology_info->cache_info.size()));
  for (int level=0; level<num_levels; ++level) {
    linesizes[level] = node_topology_info->cache_info[level].linesize;
    strides  [level] = node_topology_info->cache_info[level].stride  ;
  }
  return node_topology_info->cache_info.size();
}



extern "C"
int hwloc_system_topology()
{
  // Determine MPI (host/process) mapping
  mpi_host_mapping_t mpi_host_mapping;
  mpi_host_mapping.load();
  
#ifdef __bgq__
  // hwloc 1.6 segfaults on Blue Gene/Q
  CCTK_INFO("Running on Blue Gene/Q -- not using hwloc");
  
  CCTK_INFO("Thread CPU bindings:");
#pragma omp parallel
  {
    int const num_threads = omp_get_num_threads();
    for (int thread=0; thread<num_threads; ++thread) {
      if (thread == omp_get_thread_num()) {
        int ierr;
        int const core = Kernel_ProcessorCoreID();
        int const hwthread = Kernel_ProcessorThreadID();
        int const pu = Kernel_ProcessorID();
        printf("OMP thread %d: core %d, PU %d, hardware thread %d\n",
               thread, core, pu, hwthread);
      }
#pragma omp barrier
    }
  }
  
  // Define data structure manually
  node_topology_info = new node_topology_info_t;
  int const num_cores_on_host = 16;
  int const num_cores_in_proc =
    divup(16, mpi_host_mapping.mpi_num_procs_on_host);
  node_topology_info->num_smt_threads =
    divup(omp_get_max_threads(), num_cores_in_proc);
  
  {
    // D1 cache
    int const size = 16384;
    int const linesize = 64;
    int const associativity = 8;
    node_topology_info_t::cache_info_t new_cache_info;
    new_cache_info.linesize = linesize;
    new_cache_info.stride   = size / associativity;
    node_topology_info->cache_info.push_back(new_cache_info);
  }
  {
    // D2 cache
    int const size = 32*1024*1024;
    int const linesize = 128;
    int const associativity = 16;
    node_topology_info_t::cache_info_t new_cache_info;
    new_cache_info.linesize = linesize;
    new_cache_info.stride   = size / associativity;
    node_topology_info->cache_info.push_back(new_cache_info);
  }
  
  return 0;
#endif
  
  // Determine node topology
  hwloc_topology_t topology;
  hwloc_topology_init(&topology);
  hwloc_topology_load(topology);
  
  output_support(topology);
  output_objects(topology);
  output_bindings(topology);
  // TODO: output distance matrix
  
  set_bindings(topology, mpi_host_mapping);
  output_bindings(topology);
  
  // Capture some information for later use
  node_topology_info = new node_topology_info_t;
  node_topology_info->load(topology, mpi_host_mapping);
  
  hwloc_topology_destroy(topology);
  
  return 0;
}
