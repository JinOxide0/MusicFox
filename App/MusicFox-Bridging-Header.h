#ifndef MusicFox_Bridging_Header_h
#define MusicFox_Bridging_Header_h

#include <stddef.h>

/// Calls the Rust core with a JSON request and returns a JSON response.
/// The returned pointer must be released with mf_free().
char * _Nullable mf_call(const char * _Nullable input);

/// Releases a string returned by mf_call().
void mf_free(char * _Nullable pointer);

#endif /* MusicFox_Bridging_Header_h */
