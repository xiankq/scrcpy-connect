import com.genymobile.scrcpy.video.LatestInputWindow;

import java.util.ArrayList;
import java.util.List;

/** Pure Java behavioral tests; run with -ea, no Android runtime or device. */
public final class LatestInputWindowTest {
    private static final class Harness implements LatestInputWindow.Scheduler {
        long now = 1_000_000_000L;
        Runnable task;
        long due;
        Runnable retiredTask;
        int maxQueued;
        int tasksRun;
        final List<LatestInputWindow.Frame> frames = new ArrayList<>();
        LatestInputWindow window;
        boolean failSwap;
        boolean synchronousOutput;
        boolean closeDuringSwap;

        Harness(long repeatUs, float fps) {
            window = new LatestInputWindow(() -> now, this, frame -> {
                // Reservation must already exist when the first actual swap begins.
                check(window.inFlight() > 0, "reserve must precede swap");
                frames.add(frame);
                if (synchronousOutput) {
                    window.complete(frame.presentationTimeUs, 0, 12);
                }
                if (closeDuringSwap) {
                    window.close();
                }
                if (failSwap) {
                    throw new IllegalStateException("injected swap failure");
                }
            }, repeatUs, fps);
        }

        @Override
        public void post(Runnable next, long delayNs) {
            check(task == null, "at most one drain/timer task");
            task = next;
            due = now + delayNs;
            maxQueued = Math.max(maxQueued, 1);
        }

        @Override
        public void cancel(Runnable next) {
            check(task == next, "cancel the one live timer");
            retiredTask = task;
            task = null;
        }

        void ready() {
            int count = 0;
            while (task != null && due <= now) {
                check(count++ < 100, "no drain spin or recursive repeat");
                Runnable next = task;
                task = null;
                tasksRun++;
                next.run();
            }
        }

        void advance(long ns) {
            now += ns;
            ready();
        }

        void source(long sourceNs) {
            window.onSource(sourceNs);
            ready();
        }

        void output(int frame) {
            window.complete(frames.get(frame).presentationTimeUs, 0, 12);
            ready();
        }
    }

    private static void check(boolean value, String message) {
        if (!value) {
            throw new AssertionError(message);
        }
    }

    private static void boundedLatestAndFinalFrame() {
        Harness h = new Harness(0, 0);
        h.window.activate();
        h.source(100_000);
        h.source(200_000);
        h.source(300_000);
        h.source(400_000);
        h.source(500_000);
        check(h.frames.size() == 2 && h.window.inFlight() == 2, "two actual inputs maximum");
        h.output(0); // There is deliberately no later source callback.
        check(h.frames.size() == 2 && h.window.inFlight() == 1, "first output reduces the window without admitting another input");
        h.output(1);
        check(h.frames.size() == 3, "output alone actively drains final pending input");
        check(h.frames.get(2).sourceTimestampNs == 500_000, "only latest pending source survives");
        check(!h.frames.get(2).repeat, "final update is a source input");
        h.output(2);
        check(h.window.inFlight() == 0, "all exact outputs retired");
        h.advance(LatestInputWindow.STALL_NS * 2);
        check(h.window.getFailure() == null, "an empty static ledger cannot stall");
    }

    private static void activationAndCadence() {
        Harness h = new Harness(33_334, 60);
        h.source(100_000);
        check(h.frames.isEmpty(), "capture before codec.start cannot swap");
        h.window.activate();
        h.ready();
        check(h.frames.size() == 1, "activate releases first retained source");
        h.source(200_000);
        check(h.frames.size() == 1, "max-fps schedules instead of native-dropping reserved input");
        h.advance(16_666_667);
        check(h.frames.size() == 2 && h.frames.get(1).sourceTimestampNs == 200_000, "latest source at FPS deadline");
    }

    private static void staticRepeatAndStall() {
        Harness h = new Harness(33_334, 60);
        h.window.activate();
        h.source(100_000);
        h.advance(33_333_999);
        check(h.frames.size() == 1, "no premature repeat");
        h.advance(1);
        check(h.frames.size() == 2, "static first input may bootstrap with second credit");
        LatestInputWindow.Frame repeat = h.frames.get(1);
        check(repeat.repeat && repeat.sourceTimestampNs == 100_000, "repeat keeps original source age");
        check(repeat.presentationTimeUs > h.frames.get(0).presentationTimeUs, "repeat has distinct monotonic encoding PTS");
        h.advance(LatestInputWindow.STALL_NS - 33_334_000);
        check(h.window.isClosed() && h.window.getFailure() != null, "full window fails at bounded stall deadline");
        check(h.frames.size() == 2 && h.task == null, "stall neither enlarges window nor retries");
    }

    private static void exactOutputAccounting() {
        Harness h = new Harness(0, 0);
        h.window.activate();
        h.source(100_000);
        h.source(200_000);
        h.window.complete(99, LatestInputWindow.CONFIG, 20);
        h.window.complete(99, LatestInputWindow.EOS, 0);
        check(h.window.inFlight() == 2, "config and empty EOS cannot return a credit");
        h.output(1); // A larger PTS does not retire the older input.
        check(h.window.inFlight() == 1, "out-of-order output retires one exact PTS");
        h.source(300_000);
        check(h.window.inFlight() == 1 && h.frames.size() == 2, "older bootstrap reservation occupies the reduced window");
        h.output(0);
        check(h.window.inFlight() == 1 && h.frames.size() == 3, "retiring the old input admits only the latest pending input");
        h.window.complete(h.frames.get(1).presentationTimeUs, 0, 12);
        check(h.window.getFailure() != null && h.window.isClosed(), "duplicate output revokes generation");

        Harness unknown = new Harness(0, 0);
        unknown.window.activate();
        unknown.source(100_000);
        unknown.window.complete(999, 0, 12);
        check(unknown.window.getFailure() != null, "unknown media PTS fails explicitly");

        Harness partial = new Harness(0, 0);
        partial.window.activate();
        partial.source(100_000);
        partial.window.complete(partial.frames.get(0).presentationTimeUs, LatestInputWindow.PARTIAL, 12);
        check(partial.window.getFailure() != null, "partial media is rejected");

        Harness eos = new Harness(0, 0);
        eos.window.activate();
        eos.source(100_000);
        eos.window.complete(eos.frames.get(0).presentationTimeUs, LatestInputWindow.EOS, 12);
        check(eos.window.inFlight() == 0 && eos.window.getFailure() == null, "media-bearing EOS retires its exact input");
    }

    private static void steadyStaticRepeat() {
        Harness h = new Harness(33_334, 60);
        h.window.activate();
        h.source(100_000);
        h.advance(33_334_000);
        check(h.frames.size() == 2, "bootstrap can use its second credit");
        h.output(0);
        h.advance(33_334_000);
        check(h.frames.size() == 2, "first output must not enlarge the steady window");
        h.output(1);
        check(h.frames.size() == 3 && h.window.inFlight() == 1, "static repeat progresses after bootstrap drains");
        check(h.frames.get(2).repeat && h.frames.get(2).sourceTimestampNs == 100_000, "steady repeat keeps source age");
        h.source(600_000);
        h.source(700_000);
        h.advance(33_334_000);
        check(h.frames.size() == 3, "pending sources cannot bypass one live reservation");
        h.output(2);
        check(h.frames.size() == 4 && h.frames.get(3).sourceTimestampNs == 700_000, "single-window output drains the unique latest terminal update");
        h.advance(LatestInputWindow.STALL_NS);
        check(h.window.getFailure() != null && h.window.isClosed(), "steady input still has the bounded stall guard");
    }

    private static void finiteRepeatBootstrapAndIdleWakeup() {
        Harness h = new Harness(33_334, 60);
        h.window.activate();
        h.source(100_000);
        h.advance(33_334_000);
        check(h.frames.size() == 2 && h.frames.get(1).repeat, "bootstrap consumes the first repeat of the ten-repeat budget");
        h.output(0);
        check(h.window.inFlight() == 1 && h.frames.size() == 2, "bootstrap output preserves the one-input steady limit");
        h.output(1);
        for (int repeat = 2; repeat <= 10; repeat++) {
            h.advance(33_334_000);
            check(h.frames.size() == repeat + 1, "each remaining repeat submits once at its deadline");
            LatestInputWindow.Frame frame = h.frames.get(repeat);
            check(frame.repeat && frame.sourceTimestampNs == 100_000, "finite repeats preserve the original source timestamp");
            check(frame.presentationTimeUs == h.now / 1000, "finite repeats use their exact monotonic submission PTS");
            h.output(repeat);
        }
        check(h.frames.size() == 11 && h.window.inFlight() == 0, "one source produces exactly ten repeats with exact output retirement");
        check(h.task == null && h.window.getStallDeadlineNs() == 0, "exhausted repeats leave no drain, timer, or stall ledger");
        int idleTasks = h.tasksRun;
        h.advance(LatestInputWindow.STALL_NS * 20);
        check(h.frames.size() == 11 && h.tasksRun == idleTasks && h.task == null, "long static idle performs no work after the repeat quota");
        check(!h.window.isClosed() && h.window.getFailure() == null, "long idle with an empty ledger remains healthy");

        long resumedSourceNs = h.now + 1_234_000;
        h.source(resumedSourceNs);
        LatestInputWindow.Frame resumed = h.frames.get(11);
        check(h.frames.size() == 12 && !resumed.repeat && resumed.sourceTimestampNs == resumedSourceNs,
                "a unique source after idle actively submits without another callback");
        check(resumed.presentationTimeUs == resumedSourceNs / 1000, "idle wakeup preserves the new source's exact PTS");
        h.output(11);
        for (int repeat = 1; repeat <= 10; repeat++) {
            h.advance(33_334_000);
            check(h.frames.size() == 12 + repeat, "new submitted source receives a fresh ten-repeat budget");
            LatestInputWindow.Frame frame = h.frames.get(11 + repeat);
            check(frame.repeat && frame.sourceTimestampNs == resumedSourceNs, "fresh-budget repeats keep the resumed source timestamp");
            check(frame.presentationTimeUs == h.now / 1000, "fresh-budget repeats retain exact PTS");
            h.output(11 + repeat);
        }
        check(h.frames.size() == 22 && h.task == null && h.window.inFlight() == 0, "the fresh budget also stops after ten repeats");
    }

    private static void exhaustedRepeatDrainsPendingSource() {
        Harness h = new Harness(33_334, 60);
        h.window.activate();
        h.source(100_000);
        h.output(0);
        for (int repeat = 1; repeat <= 10; repeat++) {
            h.advance(33_334_000);
            check(h.frames.size() == repeat + 1 && h.frames.get(repeat).repeat, "consume exactly one repeat per returned credit");
            if (repeat < 10) {
                h.output(repeat);
            }
        }
        check(h.window.inFlight() == 1 && h.task != null && h.window.getStallDeadlineNs() == h.now + LatestInputWindow.STALL_NS,
                "zero repeat quota retains the stall watch while the final repeat is live");
        long latestSourceNs = h.now + 1_000_000;
        h.source(latestSourceNs - 100_000);
        h.source(latestSourceNs);
        check(h.frames.size() == 11 && h.window.inFlight() == 1, "source callbacks cannot replenish or bypass a live final repeat");
        h.advance(33_334_000);
        h.output(10); // No source callback follows the final repeat's exact output.
        LatestInputWindow.Frame source = h.frames.get(11);
        check(h.frames.size() == 12 && !source.repeat && source.sourceTimestampNs == latestSourceNs,
                "zero repeat quota still actively drains the latest pending source on output");
        check(source.presentationTimeUs == latestSourceNs / 1000, "pending source retains its exact PTS");
        h.output(11);
        for (int repeat = 1; repeat <= 10; repeat++) {
            h.advance(33_334_000);
            check(h.frames.size() == 12 + repeat, "the actual pending-source submission starts one fresh budget");
            h.output(11 + repeat);
        }
        check(h.task == null && h.window.inFlight() == 0, "coalesced source callbacks do not accumulate repeat budgets");

        Harness stalled = new Harness(33_334, 60);
        stalled.window.activate();
        stalled.source(100_000);
        stalled.output(0);
        for (int repeat = 1; repeat <= 10; repeat++) {
            stalled.advance(33_334_000);
            if (repeat < 10) {
                stalled.output(repeat);
            }
        }
        stalled.advance(LatestInputWindow.STALL_NS);
        check(stalled.window.isClosed() && stalled.window.getFailure() != null && stalled.frames.size() == 11 && stalled.task == null,
                "an unretired final repeat still fails at the three-second stall deadline");
    }

    private static void synchronousOutputAndSwapFailure() {
        Harness h = new Harness(0, 0);
        h.synchronousOutput = true;
        h.window.activate();
        h.source(100_000);
        check(h.window.inFlight() == 0 && h.window.getFailure() == null, "output before swap returns sees reservation");
        h.source(100_000);
        check(h.frames.get(1).presentationTimeUs > h.frames.get(0).presentationTimeUs, "colliding source PTS explicitly remapped");
        check(h.frames.get(1).sourceTimestampNs == 100_000, "mapping never rewrites source age");

        Harness failed = new Harness(0, 0);
        failed.failSwap = true;
        failed.window.activate();
        failed.source(100_000);
        failed.source(200_000);
        check(failed.window.isClosed() && failed.window.getFailure() != null && failed.frames.size() == 1, "failed swap revokes whole generation");
    }

    private static void closeAndGenerationIsolation() {
        Harness old = new Harness(33_334, 60);
        old.window.activate();
        old.source(100_000);
        Runnable stale = old.task;
        old.window.close();
        old.window.complete(old.frames.get(0).presentationTimeUs, 0, 12);
        old.window.onSource(999_000);
        old.window.activate();
        stale.run(); // Even a timer already dequeued when close happened is harmless.
        check(old.frames.size() == 1 && old.task == null && old.window.inFlight() == 0, "closed generation rejects stale callbacks");
        Harness fresh = new Harness(0, 0);
        fresh.window.activate();
        fresh.source(200_000);
        check(fresh.frames.size() == 1 && fresh.window.inFlight() == 1, "new generation has independent ledger");
        old.window.complete(fresh.frames.get(0).presentationTimeUs, 0, 12);
        check(fresh.window.inFlight() == 1, "old output cannot retire a new generation input");

        Harness reserve = new Harness(33_334, 60);
        reserve.closeDuringSwap = true;
        reserve.window.activate();
        reserve.source(100_000);
        reserve.advance(100_000_000);
        check(reserve.frames.size() == 1 && reserve.window.isClosed() && reserve.task == null, "pause during reserved swap cancels all later work");
    }

    public static void main(String[] args) {
        boundedLatestAndFinalFrame();
        activationAndCadence();
        staticRepeatAndStall();
        steadyStaticRepeat();
        finiteRepeatBootstrapAndIdleWakeup();
        exhaustedRepeatDrainsPendingSource();
        exactOutputAccounting();
        synchronousOutputAndSwapFailure();
        closeAndGenerationIsolation();
        System.out.println("LatestInputWindowTest: 9 behavioral scenarios passed");
    }
}
