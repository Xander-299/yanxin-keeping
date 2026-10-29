// 端上推理基准探针（阶段二任务 1：SPEC-local-ai.md §4.2 的「设备 × 模型」矩阵）。
//
// 为什么自己写：`llama-bench` 只给 pp/tg 的 tok/s，拿不到本表要的
// 「冷加载 ms / 首 token ms / 每轮 RSS / 长跑降频」；而这几项恰恰决定
// 「这台手机能不能跑、跑起来会不会烫」。所以这里直接调 llama.cpp 的 C API，
// 一轮一轮跑真实中文 prompt，把每轮的耗时与内存打到 stdout（`KEY=value` 行，
// 由 tool/llm_bench/run_bench.ps1 汇总成 markdown 表）。
//
// 刻意**不做**的事：
// - 不采样花活：贪心解码，保证不同模型之间比的是同一件事（算力），不是随机性；
// - 不写死模型名 / 上下文：全部命令行给，避免「基准脚本里藏着结论」；
// - 不记录 prompt 内容到日志以外的任何地方（本探针只跑合成财报文本，不含真实账本）。
//
// 构建：tool/llm_bench/build_android.ps1（NDK + llama.cpp 静态库，产物 bench_android）

#include "llama.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace {

using clock_t_ = std::chrono::steady_clock;

double ms_since(clock_t_::time_point t0) {
  return std::chrono::duration<double, std::milli>(clock_t_::now() - t0).count();
}

// 从 /proc/self/status 读某个字段（kB）。读不到返回 -1。
long read_proc_status_kb(const char * key) {
  std::ifstream f("/proc/self/status");
  if (!f) return -1;
  std::string line;
  const std::string prefix = std::string(key) + ":";
  while (std::getline(f, line)) {
    if (line.rfind(prefix, 0) == 0) {
      long v = -1;
      if (sscanf(line.c_str() + prefix.size(), "%ld", &v) == 1) return v;
      return -1;
    }
  }
  return -1;
}

// 读一个单值 sysfs 文件（温度 / 频率），读不到返回 -1。
long read_sysfs_int(const std::string & path) {
  if (path.empty()) return -1;
  std::ifstream f(path);
  if (!f) return -1;
  long v = -1;
  if (!(f >> v)) return -1;
  return v;
}

struct Args {
  std::string model;
  std::string prompt = "我这个月花了多少钱？";
  std::string prompt_file;
  std::string temp_path;
  std::string freq_path;
  int n_ctx = 2048;
  int n_predict = 128;
  int threads = 4;
  int rounds = 3;
  int minutes = 0;  // >0 时长跑模式：跑满分钟数，用于看温升与降频
  bool raw_prompt = false;  // true = 不加 chat template
};

void usage() {
  std::fprintf(stderr,
      "usage: bench_android -m model.gguf [-c ctx] [-n predict] [-t threads]\n"
      "                     [-r rounds | --minutes M] [-p prompt] [--prompt-file f]\n"
      "                     [--raw-prompt] [--temp-path p] [--freq-path p]\n");
}

bool parse_args(int argc, char ** argv, Args & a) {
  for (int i = 1; i < argc; i++) {
    const std::string k = argv[i];
    auto next = [&](const char * name) -> std::string {
      if (i + 1 >= argc) { std::fprintf(stderr, "missing value for %s\n", name); std::exit(2); }
      return argv[++i];
    };
    if (k == "-m" || k == "--model") a.model = next("-m");
    else if (k == "-c" || k == "--ctx") a.n_ctx = std::atoi(next("-c").c_str());
    else if (k == "-n" || k == "--predict") a.n_predict = std::atoi(next("-n").c_str());
    else if (k == "-t" || k == "--threads") a.threads = std::atoi(next("-t").c_str());
    else if (k == "-r" || k == "--rounds") a.rounds = std::atoi(next("-r").c_str());
    else if (k == "--minutes") a.minutes = std::atoi(next("--minutes").c_str());
    else if (k == "-p" || k == "--prompt") a.prompt = next("-p");
    else if (k == "--prompt-file") a.prompt_file = next("--prompt-file");
    else if (k == "--raw-prompt") a.raw_prompt = true;
    else if (k == "--temp-path") a.temp_path = next("--temp-path");
    else if (k == "--freq-path") a.freq_path = next("--freq-path");
    else if (k == "-h" || k == "--help") { usage(); std::exit(0); }
    else { std::fprintf(stderr, "unknown arg: %s\n", k.c_str()); return false; }
  }
  return !a.model.empty();
}

// prompt 文件里用单独一行 `---` 分隔多条问题（每轮轮换，模拟连续问答）。
std::vector<std::string> load_prompts(const Args & a) {
  if (a.prompt_file.empty()) return {a.prompt};
  std::ifstream f(a.prompt_file);
  if (!f) {
    std::fprintf(stderr, "cannot open prompt file: %s\n", a.prompt_file.c_str());
    std::exit(2);
  }
  std::vector<std::string> out;
  std::string line, cur;
  while (std::getline(f, line)) {
    if (line == "---") {
      if (!cur.empty()) out.push_back(cur);
      cur.clear();
    } else {
      cur += line;
      cur += "\n";
    }
  }
  if (!cur.empty()) out.push_back(cur);
  if (out.empty()) out.push_back(a.prompt);
  return out;
}

// 把一条用户问题包成模型自己的 chat 模板（模板不支持时退回纯文本）。
std::string apply_chat_template(struct llama_model * model, const std::string & user) {
  const char * tmpl = llama_model_chat_template(model, nullptr);
  if (tmpl == nullptr) return user;
  const llama_chat_message msg = {"user", user.c_str()};
  std::vector<char> buf(2 * (user.size() + 512), '\0');
  int32_t n = llama_chat_apply_template(tmpl, &msg, 1, true, buf.data(), (int32_t) buf.size());
  if (n <= 0) return user;
  if ((size_t) n > buf.size()) {
    buf.assign(n + 1, '\0');
    n = llama_chat_apply_template(tmpl, &msg, 1, true, buf.data(), (int32_t) buf.size());
    if (n <= 0) return user;
  }
  return std::string(buf.data(), (size_t) n);
}

}  // namespace

int main(int argc, char ** argv) {
  Args a;
  if (!parse_args(argc, argv, a)) { usage(); return 2; }
  const std::vector<std::string> prompts = load_prompts(a);

  llama_backend_init();

  // ── 冷加载 ──
  llama_model_params mparams = llama_model_default_params();
  mparams.n_gpu_layers = 0;  // 端上只有 CPU 后端，显式写死，避免"看起来跑了 GPU"
  const auto t_load0 = clock_t_::now();
  struct llama_model * model = llama_model_load_from_file(a.model.c_str(), mparams);
  const double load_ms = ms_since(t_load0);
  if (model == nullptr) {
    std::fprintf(stderr, "LOAD_FAILED=%s\n", a.model.c_str());
    return 1;
  }
  const long rss_after_load_kb = read_proc_status_kb("VmRSS");

  const llama_vocab * vocab = llama_model_get_vocab(model);
  char desc[256] = {0};
  llama_model_desc(model, desc, sizeof(desc));
  const uint64_t n_params = llama_model_n_params(model);
  const uint64_t model_bytes = llama_model_size(model);
  const int32_t n_ctx_train = llama_model_n_ctx_train(model);

  std::printf("CFG ctx=%d predict=%d threads=%d rounds=%d minutes=%d raw=%d\n",
              a.n_ctx, a.n_predict, a.threads, a.rounds, a.minutes, a.raw_prompt ? 1 : 0);
  std::printf("META desc=%s n_params=%llu model_bytes=%llu n_ctx_train=%d\n",
              desc, (unsigned long long) n_params, (unsigned long long) model_bytes, n_ctx_train);
  std::printf("LOAD load_ms=%.1f rss_after_load_kb=%ld\n", load_ms, rss_after_load_kb);

  llama_context_params cparams = llama_context_default_params();
  cparams.n_ctx = (uint32_t) a.n_ctx;
  cparams.n_batch = (uint32_t) (a.n_ctx > 512 ? 512 : a.n_ctx);
  cparams.n_threads = a.threads;
  cparams.n_threads_batch = a.threads;
  struct llama_context * ctx = llama_init_from_model(model, cparams);
  if (ctx == nullptr) {
    std::fprintf(stderr, "CTX_FAILED\n");
    llama_model_free(model);
    return 1;
  }

  llama_sampler * smpl = llama_sampler_chain_init(llama_sampler_chain_default_params());
  llama_sampler_chain_add(smpl, llama_sampler_init_greedy());

  const auto t_all0 = clock_t_::now();
  double ttft_sum = 0, pp_tps_sum = 0, tg_tps_sum = 0;
  int rounds_done = 0;
  long peak_rss_kb = rss_after_load_kb;

  for (int round = 1;; round++) {
    if (a.minutes > 0) {
      if (ms_since(t_all0) > a.minutes * 60.0 * 1000.0) break;
    } else if (round > a.rounds) {
      break;
    }

    const std::string user = prompts[(size_t) (round - 1) % prompts.size()];
    const std::string text = a.raw_prompt ? user : apply_chat_template(model, user);

    // 每轮从干净上下文开始：Q&A 场景下每次提问都是独立会话（也避免 KV 越滚越大）
    llama_memory_clear(llama_get_memory(ctx), true);

    std::vector<llama_token> toks(text.size() + 32);
    int32_t n_tok = llama_tokenize(vocab, text.c_str(), (int32_t) text.size(),
                                  toks.data(), (int32_t) toks.size(),
                                  /*add_special=*/!a.raw_prompt, /*parse_special=*/true);
    if (n_tok < 0) {
      toks.resize((size_t) -n_tok + 8);
      n_tok = llama_tokenize(vocab, text.c_str(), (int32_t) text.size(),
                             toks.data(), (int32_t) toks.size(), !a.raw_prompt, true);
    }
    if (n_tok <= 0) {
      std::fprintf(stderr, "TOKENIZE_FAILED round=%d\n", round);
      break;
    }
    toks.resize((size_t) n_tok);
    if (n_tok >= a.n_ctx) {
      std::fprintf(stderr, "PROMPT_TOO_LONG round=%d n_tok=%d ctx=%d\n", round, n_tok, a.n_ctx);
      break;
    }

    // ── prefill（首 token 之前的全部计算）──
    const auto t_pp0 = clock_t_::now();
    if (llama_decode(ctx, llama_batch_get_one(toks.data(), n_tok)) != 0) {
      std::fprintf(stderr, "DECODE_FAILED round=%d\n", round);
      break;
    }
    llama_token cur = llama_sampler_sample(smpl, ctx, -1);
    const double ttft_ms = ms_since(t_pp0);
    const double pp_ms = ttft_ms;  // 贪心采样开销可忽略，prefill ≈ 首 token 时间

    // ── decode（逐 token 生成）──
    const auto t_tg0 = clock_t_::now();
    int gen = 1;
    llama_token one[1] = {cur};
    while (gen < a.n_predict && !llama_vocab_is_eog(vocab, cur)) {
      if (llama_decode(ctx, llama_batch_get_one(one, 1)) != 0) break;
      cur = llama_sampler_sample(smpl, ctx, -1);
      one[0] = cur;
      gen++;
    }
    const double gen_ms = ms_since(t_tg0);
    const double tg_tps = gen > 1 && gen_ms > 0 ? (gen - 1) * 1000.0 / gen_ms : 0;
    const double pp_tps = pp_ms > 0 ? n_tok * 1000.0 / pp_ms : 0;

    const long rss_kb = read_proc_status_kb("VmRSS");
    const long hwm_kb = read_proc_status_kb("VmHWM");
    if (hwm_kb > peak_rss_kb) peak_rss_kb = hwm_kb;
    const long temp_c = read_sysfs_int(a.temp_path);
    const long freq_khz = read_sysfs_int(a.freq_path);

    std::printf(
        "ROUND i=%d elapsed_s=%.1f prompt_tok=%d gen_tok=%d ttft_ms=%.1f pp_tps=%.2f "
        "gen_ms=%.1f tg_tps=%.2f rss_kb=%ld hwm_kb=%ld temp_mc=%ld freq_khz=%ld\n",
        round, ms_since(t_all0) / 1000.0, n_tok, gen, ttft_ms, pp_tps, gen_ms, tg_tps,
        rss_kb, hwm_kb, temp_c, freq_khz);
    std::fflush(stdout);

    ttft_sum += ttft_ms;
    pp_tps_sum += pp_tps;
    tg_tps_sum += tg_tps;
    rounds_done++;
  }

  if (rounds_done > 0) {
    std::printf(
        "SUMMARY rounds=%d load_ms=%.1f ttft_ms_avg=%.1f pp_tps_avg=%.2f tg_tps_avg=%.2f "
        "peak_rss_kb=%ld wall_s=%.1f\n",
        rounds_done, load_ms, ttft_sum / rounds_done, pp_tps_sum / rounds_done,
        tg_tps_sum / rounds_done, peak_rss_kb, ms_since(t_all0) / 1000.0);
  }

  llama_sampler_free(smpl);
  llama_free(ctx);
  llama_model_free(model);
  llama_backend_free();
  return rounds_done > 0 ? 0 : 1;
}
