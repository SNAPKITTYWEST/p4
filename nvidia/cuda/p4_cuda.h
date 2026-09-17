/* nvidia/cuda/p4_cuda.h */
#ifndef P4_CUDA_H
#define P4_CUDA_H
#include "../../abi/p4.h"
#ifdef __cplusplus
extern "C" {
#endif

p4_status p4_cuda_init(void);
p4_status p4_cuda_shutdown(void);

p4_status p4_cuda_device_create(uint32_t index, p4_device* out);
p4_status p4_cuda_device_destroy(p4_device dev);
p4_status p4_cuda_device_architecture(p4_device dev, const char** out_name);
p4_status p4_cuda_device_capabilities(p4_device dev, p4_capabilities* out);

p4_status p4_cuda_buffer_create(p4_device dev, uint64_t bytes, p4_dtype dt, p4_buffer* out);
p4_status p4_cuda_buffer_upload(p4_buffer buf, const void* src, uint64_t bytes, uint64_t offset);
p4_status p4_cuda_buffer_read(p4_buffer buf, void* dst, uint64_t bytes, uint64_t offset);
p4_status p4_cuda_buffer_destroy(p4_buffer buf);

p4_status p4_cuda_pipeline_create(p4_device dev, p4_kernel_id id, p4_dtype dt,
                                  const char* source, const char* entry_point,
                                  p4_kernel* out);
p4_status p4_cuda_pipeline_destroy(p4_kernel k);

p4_status p4_cuda_command_buffer_create(p4_device dev, p4_command* out);
p4_status p4_cuda_dispatch(p4_command cmd, p4_kernel k,
                           const p4_extent3* grid, const p4_extent3* block,
                           uint32_t shared_bytes);
p4_status p4_cuda_commit(p4_command cmd, p4_event* out_evt);
p4_status p4_cuda_wait(p4_event evt, uint64_t timeout_ns);
p4_status p4_cuda_destroy(p4_command cmd);

#ifdef __cplusplus
}
#endif
#endif
