/* abi/p4.h — the single stable interoperability boundary. */
#ifndef P4_H
#define P4_H

#include "types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ---- lifecycle ---------------------------------------------------------- */
p4_status p4_init(void);
p4_status p4_shutdown(void);

/* ---- device ------------------------------------------------------------- */
p4_status p4_device_enumerate(p4_backend backend, p4_device* out, uint32_t* count);
p4_status p4_device_create(p4_backend backend, uint32_t index, p4_device* out);
p4_status p4_device_architecture(p4_device dev, const char** out_name);
p4_status p4_device_capabilities(p4_device dev, p4_capabilities* out);
p4_status p4_device_destroy(p4_device dev);

/* ---- buffer ------------------------------------------------------------- */
p4_status p4_buffer_create(p4_device dev, uint64_t bytes, p4_dtype dt, p4_buffer* out);
p4_status p4_buffer_upload(p4_buffer buf, const void* src, uint64_t bytes, uint64_t offset);
p4_status p4_buffer_read(p4_buffer buf, void* dst, uint64_t bytes, uint64_t offset);
p4_status p4_buffer_bytes(p4_buffer buf, uint64_t* out);
p4_status p4_buffer_destroy(p4_buffer buf);

/* ---- kernel / pipeline -------------------------------------------------- */
p4_status p4_kernel_create(p4_device dev,
                           p4_kernel_id id,
                           p4_dtype dt,
                           const char* source,
                           const char* entry_point,
                           p4_kernel* out);
p4_status p4_kernel_source(p4_kernel k, const char** out_src, uint64_t* out_len);
p4_status p4_kernel_backend(p4_kernel k, p4_backend* out);
p4_status p4_kernel_capabilities(p4_kernel k, p4_capabilities* out);
p4_status p4_kernel_destroy(p4_kernel k);

/* ---- command ------------------------------------------------------------ */
p4_status p4_command_begin(p4_device dev, p4_command* out);
p4_status p4_command_bind_buffer(p4_command cmd, p4_buffer buf, uint32_t index);
p4_status p4_command_dispatch(p4_command cmd, p4_kernel k,
                              const p4_extent3* grid,
                              const p4_extent3* block,
                              uint32_t shared_bytes);
p4_status p4_command_commit(p4_command cmd, p4_event* out_evt);
p4_status p4_command_sync(p4_command cmd);
p4_status p4_command_destroy(p4_command cmd);

/* ---- event -------------------------------------------------------------- */
p4_status p4_event_wait(p4_event evt, uint64_t timeout_ns);
p4_status p4_event_query(p4_event evt, uint32_t* complete);
p4_status p4_event_destroy(p4_event evt);

/* ---- registry ----------------------------------------------------------- */
p4_status p4_registry_register(const p4_kernel_record* rec);
p4_status p4_registry_lookup(p4_kernel_id id, p4_backend b, p4_dtype dt,
                             p4_kernel_record* out);
p4_status p4_registry_dump(const p4_kernel_record** out, uint32_t* count);

/* ---- verification ------------------------------------------------------- */
p4_status p4_verify_against_reference(const void* gpu, const void* ref,
                                      uint64_t count, p4_dtype dt,
                                      double atol, double rtol,
                                      p4_error_report* out);

#ifdef __cplusplus
}
#endif
#endif /* P4_H */
