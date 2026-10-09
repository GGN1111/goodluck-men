#include <fcntl.h>
#include <unistd.h>

#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include <android/log.h>

#include "llama.h"

// Flat, primitive-only C API consumed by Dart FFI (lib/inference/llama_engine.dart).
// All llama.cpp struct handling lives here so Dart never touches C ABI layouts.
//
// Error/return conventions:
//   sr_create        -> engine pointer, or nullptr on failure (*err set):
//                         1 = model load failed, 2 = context alloc failed (oom)
//   sr_setup         -> 0 ok, -1 no engine, -2 chain alloc failed, -3 grammar build failed
//   sr_feed          -> 0 ok, <0 decode failed
//   sr_sample        -> >0 bytes written to out, 0 = EOS/finished, <0 error (-2 decode)
//   sr_free          -> void

namespace {

struct SrEngine {
  llama_model* model = nullptr;
  llama_context* ctx = nullptr;
  const llama_vocab* vocab = nullptr;
  llama_sampler* chain = nullptr;
  llama_token eos = -1;
  bool prompt_fed = false;
};

std::once_flag g_backend_once;

void ensure_backend() {
  std::call_once(g_backend_once, [] { llama_backend_init(); });
}

// llama.cpp reports GBNF parse errors to stderr (fprintf in llama-grammar.cpp),
// which a Flutter app never surfaces. Redirect fd 2 into a pipe around the
// grammar build and forward whatever is written to logcat so a bad grammar
// fails loudly instead of as an opaque -1.
class StderrCapture {
 public:
  StderrCapture() {
    int fds[2];
    if (pipe(fds) != 0) return;
    saved_ = dup(STDERR_FILENO);
    if (saved_ < 0 || dup2(fds[1], STDERR_FILENO) < 0) {
      if (saved_ >= 0) close(saved_);
      saved_ = -1;
      close(fds[0]);
      close(fds[1]);
      return;
    }
    close(fds[1]);
    read_fd_ = fds[0];
  }

  void stop_and_log() {
    if (read_fd_ < 0) return;
    fflush(stderr);
    dup2(saved_, STDERR_FILENO);
    close(saved_);
    saved_ = -1;
    fcntl(read_fd_, F_SETFL, O_NONBLOCK);
    char buf[512];
    ssize_t n;
    while ((n = read(read_fd_, buf, sizeof(buf) - 1)) > 0) {
      buf[n] = '\0';
      __android_log_print(ANDROID_LOG_ERROR, "llama", "%s", buf);
    }
    close(read_fd_);
    read_fd_ = -1;
  }

  ~StderrCapture() { stop_and_log(); }

 private:
  int saved_ = -1;
  int read_fd_ = -1;
};

}  // namespace

extern "C" {

SrEngine* sr_create(const char* model_path, int32_t n_ctx, int32_t n_threads,
                    int32_t* err) {
  ensure_backend();
  if (err) *err = 0;

  SrEngine* e = new SrEngine();

  auto mparams = llama_model_default_params();
  e->model = llama_model_load_from_file(model_path, mparams);
  if (!e->model) {
    if (err) *err = 1;
    delete e;
    return nullptr;
  }

  auto cparams = llama_context_default_params();
  cparams.n_ctx = n_ctx > 0 ? static_cast<uint32_t>(n_ctx) : 4096;
  cparams.n_batch = cparams.n_ctx;
  cparams.n_threads = n_threads > 0 ? n_threads : 4;
  cparams.n_threads_batch = cparams.n_threads;
  e->ctx = llama_init_from_model(e->model, cparams);
  if (!e->ctx) {
    if (err) *err = 2;
    llama_model_free(e->model);
    delete e;
    return nullptr;
  }

  e->vocab = llama_model_get_vocab(e->model);
  e->eos = llama_vocab_eos(e->vocab);
  return e;
}

int32_t sr_setup(SrEngine* e, const char* grammar_str, const char* grammar_root,
                 int32_t seed, float temp, float top_p) {
  if (!e) return -1;
  auto sparams = llama_sampler_chain_default_params();
  e->chain = llama_sampler_chain_init(sparams);
  if (!e->chain) return -2;

  // Grammar first: masks disallowed tokens to -inf so every later sampler
  // only ever selects grammar-valid tokens. dist must be last (it selects).
  if (grammar_str && grammar_root) {
    __android_log_print(ANDROID_LOG_INFO, "llama", "sr_setup grammar_chars=%zu root=%s",
                        strlen(grammar_str), grammar_root);
    llama_sampler* g;
    {
      StderrCapture cap;
      g = llama_sampler_init_grammar(e->vocab, grammar_str, grammar_root);
      cap.stop_and_log();
    }
    if (!g) {
      llama_sampler_free(e->chain);
      e->chain = nullptr;
      return -3;  // invalid grammar
    }
    llama_sampler_chain_add(e->chain, g);
  }
  if (temp > 0.0f) {
    llama_sampler_chain_add(e->chain, llama_sampler_init_temp(temp));
  }
  if (top_p > 0.0f && top_p < 1.0f) {
    llama_sampler_chain_add(e->chain, llama_sampler_init_top_p(top_p, 1));
  }
  uint32_t s = seed >= 0 ? static_cast<uint32_t>(seed)
                         : static_cast<uint32_t>(-1);  // -1 => LLAMA_DEFAULT_SEED
  llama_sampler_chain_add(e->chain, llama_sampler_init_dist(s));
  return 0;
}

int32_t sr_feed(SrEngine* e, const char* prompt) {
  if (!e || !e->ctx || !prompt) return -1;
  const int32_t len = static_cast<int32_t>(std::strlen(prompt));
  // Over-allocate: each token is at least 1 byte, so len is a safe upper bound.
  std::vector<llama_token> toks(len + 8);
  int32_t n = llama_tokenize(e->vocab, prompt, len, toks.data(),
                             static_cast<int32_t>(toks.size()), true, false);
  if (n < 0) {
    // Buffer too small: -n is the required count. Resize and retry once.
    toks.resize(-n);
    n = llama_tokenize(e->vocab, prompt, len, toks.data(),
                       static_cast<int32_t>(toks.size()), true, false);
    if (n < 0) return -1;
  }
  if (n == 0) return -1;

  llama_batch batch = llama_batch_get_one(toks.data(), n);
  if (llama_decode(e->ctx, batch) != 0) return -1;
  e->prompt_fed = true;
  return 0;
}

int32_t sr_sample(SrEngine* e, char* out, int32_t out_cap) {
  if (!e || !e->ctx || !e->chain || !out || out_cap <= 0) return -1;

  const llama_token token = llama_sampler_sample(e->chain, e->ctx, -1);

  // Log the piece BEFORE accept so a grammar abort shows the full token
  // sequence that led to it (accept throws on empty stack -> SIGABRT).
  {
    char pd[512];
    int32_t pn = llama_token_to_piece(e->vocab, token, pd, (int)sizeof(pd), 0, false);
    if (pn < 0) pn = 0;
    if (pn >= (int)sizeof(pd)) pn = (int)sizeof(pd) - 1;
    pd[pn] = 0;
    for (int32_t i = 0; i < pn; i++) {
      if (pd[i] == '\n') { pd[i] = '\\'; if (i + 1 < (int)sizeof(pd) - 1) { pd[i+1] = 'n'; } }
    }
    __android_log_print(ANDROID_LOG_INFO, "llama", "sr_sample tok=%d piece='%s'", token, pd);
  }

  llama_sampler_accept(e->chain, token);

  if (e->eos >= 0 && token == e->eos) return 0;  // EOS -> caller stops

  int32_t n = llama_token_to_piece(e->vocab, token, out, out_cap, 0, false);
  if (n < 0) {
    // Buffer too small on retry with a small cap — treat as error (caller
    // should pass >=256 bytes; typical BPE pieces are << 32).
    n = llama_token_to_piece(e->vocab, token, out, out_cap, 0, false);
    if (n < 0) return -1;
  }

  // Advance context with this token so the next sample sees the next logits.
  llama_token tok = token;
  llama_batch batch = llama_batch_get_one(&tok, 1);
  if (llama_decode(e->ctx, batch) != 0) return -2;

  // n == 0 (empty piece / special token, non-EOS) -> -3: emit nothing, continue.
  return n == 0 ? -3 : n;
}

void sr_free(SrEngine* e) {
  if (!e) return;
  if (e->chain) llama_sampler_free(e->chain);
  if (e->ctx) llama_free(e->ctx);
  if (e->model) llama_model_free(e->model);
  delete e;
}

}  // extern "C"
