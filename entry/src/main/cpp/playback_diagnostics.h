#pragma once
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <deque>
#include <mutex>
#include <thread>

// Bounded, non-waiting producer. Only the worker touches the system log sink.
class PlaybackDiagnostics {
public:
    using Sink = void (*)(int, const char *);
    explicit PlaybackDiagnostics(Sink sink) : sink_(sink), worker_([this] { Run(); }) {}
    ~PlaybackDiagnostics() {
        { std::lock_guard<std::mutex> guard(lock_); stop_ = true; }
        ready_.notify_one();
        worker_.join();
    }
    bool Enabled() const { return enabled_.load(std::memory_order_relaxed); }
    void SetEnabled(bool enabled) {
        std::lock_guard<std::mutex> guard(lock_);
        enabled_.store(enabled, std::memory_order_relaxed);
        queue_.clear();
        dropped_.store(0);
        budget_ = 0;
        window_ = std::chrono::steady_clock::now();
        ready_.notify_one();
    }
    void Submit(int level, const char *message) {
        if (!Enabled()) return;
        std::unique_lock<std::mutex> guard(lock_, std::try_to_lock);
        if (!guard.owns_lock()) { dropped_.fetch_add(1); return; }
        if (!Enabled()) return;
        const auto now = std::chrono::steady_clock::now();
        if (now - window_ >= std::chrono::seconds(1)) { window_ = now; budget_ = 0; }
        if (queue_.size() >= 256 || budget_ >= 400) { dropped_.fetch_add(1); return; }
        ++budget_;
        Entry entry{};
        entry.level = level;
        const auto micros = std::chrono::duration_cast<std::chrono::microseconds>(now.time_since_epoch()).count();
        std::snprintf(entry.text, sizeof(entry.text), "t=%lld tid=%zu %s",
                      static_cast<long long>(micros), std::hash<std::thread::id>{}(std::this_thread::get_id()), message);
        queue_.push_back(entry);
        ready_.notify_one();
    }
private:
    struct Entry { int level; char text[2304]; };
    Sink sink_;
    std::atomic<bool> enabled_{false};
    std::atomic<unsigned> dropped_{0};
    std::mutex lock_;
    std::condition_variable ready_;
    std::deque<Entry> queue_;
    bool stop_ = false;
    unsigned budget_ = 0;
    std::chrono::steady_clock::time_point window_{};
    std::thread worker_;
    void Run() {
        auto report = std::chrono::steady_clock::now();
        for (;;) {
            Entry entry{};
            bool have = false;
            {
                std::unique_lock<std::mutex> guard(lock_);
                ready_.wait_for(guard, std::chrono::seconds(1), [this] { return stop_ || !queue_.empty(); });
                if (stop_) return;
                if (!queue_.empty()) { entry = queue_.front(); queue_.pop_front(); have = true; }
            }
            if (have && Enabled()) sink_(entry.level, entry.text);
            const auto now = std::chrono::steady_clock::now();
            if (now - report >= std::chrono::seconds(1)) {
                report = now;
                const unsigned dropped = dropped_.exchange(0);
                if (dropped && Enabled()) {
                    char text[128];
                    std::snprintf(text, sizeof(text), "[TraceBudget] omitted=%u (queue/rate contention)", dropped);
                    sink_(3, text);
                }
            }
        }
    }
};
