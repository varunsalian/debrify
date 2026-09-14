package com.tekartik.sqflite;

import static org.junit.Assert.*;

import java.nio.ByteBuffer;
import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 28)
public class EngineLifecycleTest {
    private SqflitePlugin engine() throws Exception {
        SqflitePlugin plugin = new SqflitePlugin(RuntimeEnvironment.getApplication());
        Field channel = SqflitePlugin.class.getDeclaredField("methodChannel");
        channel.setAccessible(true);
        channel.set(plugin, new MethodChannel(new BinaryMessenger() {
            public void send(String channel, ByteBuffer message) {}
            public void send(String channel, ByteBuffer message, BinaryReply reply) {}
            public void setMessageHandler(String channel, BinaryMessageHandler handler) {}
        }, "test"));
        return plugin;
    }

    private Map<String, Object> args(Object... entries) {
        Map<String, Object> values = new HashMap<>();
        for (int i = 0; i < entries.length; i += 2) values.put((String) entries[i], entries[i + 1]);
        return values;
    }

    private Object call(SqflitePlugin plugin, String method, Map<String, Object> args) throws Exception {
        CountDownLatch done = new CountDownLatch(1);
        Object[] value = new Object[1];
        String[] failure = new String[1];
        plugin.onMethodCall(new MethodCall(method, args), new MethodChannel.Result() {
            public void success(Object result) { value[0] = result; done.countDown(); }
            public void error(String code, String message, Object details) { failure[0] = code + ": " + message; done.countDown(); }
            public void notImplemented() { failure[0] = "not implemented"; done.countDown(); }
        });
        assertTrue("SQL call stranded: " + method, done.await(5, TimeUnit.SECONDS));
        assertNull(failure[0], failure[0]);
        return value[0];
    }

    private int open(SqflitePlugin plugin, String name) throws Exception {
        String path = RuntimeEnvironment.getApplication().getDatabasePath(name).getPath();
        return (Integer) ((Map<?, ?>) call(plugin, "openDatabase", args("path", path))).get("id");
    }

    @Test public void liveEnginesDoNotShareNativeHandles() throws Exception {
        SqflitePlugin first = engine();
        SqflitePlugin second = engine();
        int a = open(first, "same-path.db");
        int b = open(second, "same-path.db");
        try {
            assertNotSame("A second engine must not inherit another engine's transaction queue",
                    first.databaseMap.get(a), second.databaseMap.get(b));
        } finally {
            call(first, "closeDatabase", args("id", a));
            if (second.databaseMap.containsKey(b)) call(second, "closeDatabase", args("id", b));
        }
    }

    @Test public void detachClosesUnfinishedTransactionAndPreservesCommittedData() throws Exception {
        SqflitePlugin old = engine();
        int id = open(old, "reopen.db");
        call(old, "execute", args("id", id, "sql", "CREATE TABLE records (value INTEGER)"));
        call(old, "execute", args("id", id, "sql", "INSERT INTO records VALUES (1)"));
        Map<?, ?> begin = (Map<?, ?>) call(old, "execute", args("id", id, "sql", "BEGIN IMMEDIATE", "inTransaction", true, "transactionId", null));
        call(old, "execute", args("id", id, "sql", "INSERT INTO records VALUES (2)", "transactionId", begin.get("transactionId")));
        // This request waits behind the abandoned transaction. Detach must
        // bypass that SQL queue rather than waiting on its missing COMMIT.
        old.onMethodCall(new MethodCall("query", args("id", id, "sql", "SELECT value FROM records")),
                new MethodChannel.Result() {
                    public void success(Object result) {}
                    public void error(String code, String message, Object details) {}
                    public void notImplemented() { fail(); }
                });
        Database handle = old.databaseMap.get(id);
        old.onDetachedFromEngine(null);
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (handle.sqliteDatabase.isOpen() && System.nanoTime() < deadline) Thread.sleep(10);
        assertFalse("Dead engine retained its SQLite transaction", handle.sqliteDatabase.isOpen());
        assertFalse("Worker exited with an active transaction", handle.isInTransaction());
        SqflitePlugin fresh = engine();
        int reopened = open(fresh, "reopen.db");
        try {
            Map<?, ?> rows = (Map<?, ?>) call(fresh, "query", args("id", reopened, "sql", "SELECT value FROM records"));
            assertEquals("[[1]]", rows.get("rows").toString());
        } finally { call(fresh, "closeDatabase", args("id", reopened)); }
    }

    @Test public void oldEngineDetachDoesNotCloseOtherEnginesDatabase() throws Exception {
        SqflitePlugin first = engine();
        SqflitePlugin second = engine();
        open(first, "old.db");
        int id = open(second, "background.db");
        first.onDetachedFromEngine(null);
        try {
            call(second, "execute", args("id", id, "sql", "CREATE TABLE background_job (id INTEGER)"));
            call(second, "execute", args("id", id, "sql", "INSERT INTO background_job VALUES (1)"));
        } finally { call(second, "closeDatabase", args("id", id)); }
    }
    @Test public void detachDuringQueuedOpenCannotPublishOrLeakHandle() throws Exception {
        SqflitePlugin plugin = engine();
        Field lockField = SqflitePlugin.class.getDeclaredField("openCloseLocker");
        lockField.setAccessible(true);
        Field poolField = SqflitePlugin.class.getDeclaredField("databaseWorkerPool");
        poolField.setAccessible(true);
        CountDownLatch opened = new CountDownLatch(1);
        synchronized (lockField.get(null)) {
            plugin.onMethodCall(new MethodCall("openDatabase", args("path",
                    RuntimeEnvironment.getApplication().getDatabasePath("pending.db").getPath())),
                    new MethodChannel.Result() {
                        public void success(Object value) { opened.countDown(); }
                        public void error(String code, String message, Object details) { opened.countDown(); }
                        public void notImplemented() { fail(); }
                    });
            // The SQLite open is queued but cannot run until this lock releases.
            plugin.onDetachedFromEngine(null);
        }
        assertTrue(opened.await(5, TimeUnit.SECONDS));
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (poolField.get(plugin) != null && System.nanoTime() < deadline) Thread.sleep(10);
        assertNull("Pending open leaked its worker/connection", poolField.get(plugin));
        assertTrue(plugin.databaseMap.isEmpty());
    }

    @Test public void detachClosesAllHandlesBeforeStoppingWorker() throws Exception {
        SqflitePlugin plugin = engine();
        Database first = plugin.databaseMap.get(open(plugin, "one.db"));
        Database second = plugin.databaseMap.get(open(plugin, "two.db"));
        plugin.onDetachedFromEngine(null);
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while ((first.sqliteDatabase.isOpen() || second.sqliteDatabase.isOpen())
                && System.nanoTime() < deadline) Thread.sleep(10);
        assertFalse(first.sqliteDatabase.isOpen());
        assertFalse(second.sqliteDatabase.isOpen());
    }

    @Test public void repeatedEngineRecreationKeepsCommittedWrites() throws Exception {
        for (int i = 0; i < 12; i++) {
            SqflitePlugin plugin = engine();
            int id = open(plugin, "repeated.db");
            call(plugin, "execute", args("id", id, "sql", "CREATE TABLE IF NOT EXISTS launches (id INTEGER)"));
            call(plugin, "execute", args("id", id, "sql", "INSERT INTO launches VALUES (1)"));
            Map<?, ?> rows = (Map<?, ?>) call(plugin, "query", args("id", id, "sql", "SELECT COUNT(*) FROM launches"));
            assertEquals("[[" + (i + 1) + "]]", rows.get("rows").toString());
            Database handle = plugin.databaseMap.get(id);
            plugin.onDetachedFromEngine(null);
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
            while (handle.sqliteDatabase.isOpen() && System.nanoTime() < deadline) Thread.sleep(10);
            assertFalse(handle.sqliteDatabase.isOpen());
        }
    }

    @Test public void detachedEngineCannotReopenDatabase() throws Exception {
        SqflitePlugin plugin = engine();
        plugin.onDetachedFromEngine(null);
        String[] error = new String[1];
        plugin.onMethodCall(new MethodCall("openDatabase", args("path", ":memory:")),
                new MethodChannel.Result() {
                    public void success(Object value) { fail("Detached engine reopened a database"); }
                    public void error(String code, String message, Object details) { error[0] = message; }
                    public void notImplemented() { fail(); }
                });
        assertEquals("database engine detached", error[0]);
        assertTrue(plugin.databaseMap.isEmpty());
    }

    @Test public void failedDirectoryCreationReleasesWorker() throws Exception {
        SqflitePlugin plugin = engine();
        java.io.File blocker = new java.io.File(RuntimeEnvironment.getApplication().getFilesDir(), "blocker");
        assertTrue(blocker.createNewFile());
        CountDownLatch failed = new CountDownLatch(1);
        plugin.onMethodCall(new MethodCall("openDatabase", args("path", blocker.getPath() + "/child/db")),
                new MethodChannel.Result() {
                    public void success(Object value) { fail("Invalid path opened"); }
                    public void error(String code, String message, Object details) { failed.countDown(); }
                    public void notImplemented() { fail(); }
                });
        assertTrue(failed.await(5, TimeUnit.SECONDS));
        Field pool = SqflitePlugin.class.getDeclaredField("databaseWorkerPool");
        pool.setAccessible(true);
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
        while (pool.get(plugin) != null && System.nanoTime() < deadline) Thread.sleep(10);
        assertNull(pool.get(plugin));
        plugin.onDetachedFromEngine(null);
    }

    @Test public void synchronousDeleteDoesNotHoldAdmissionLockWhileWaitingForOpenClose() throws Exception {
        SqflitePlugin plugin = engine();
        Field openLock = SqflitePlugin.class.getDeclaredField("openCloseLocker");
        Field mapLock = SqflitePlugin.class.getDeclaredField("databaseMapLocker");
        openLock.setAccessible(true);
        mapLock.setAccessible(true);
        CountDownLatch deleted = new CountDownLatch(1);
        Thread deleter = new Thread(() -> plugin.onMethodCall(new MethodCall("deleteDatabase",
                args("path", RuntimeEnvironment.getApplication().getDatabasePath("delete.db").getPath())),
                new MethodChannel.Result() {
                    public void success(Object result) { deleted.countDown(); }
                    public void error(String code, String message, Object details) { deleted.countDown(); }
                    public void notImplemented() { deleted.countDown(); }
                }));
        CountDownLatch admissionAvailable = new CountDownLatch(1);
        Object admission = mapLock.get(null);
        Thread publisher = new Thread(() -> {
            synchronized (admission) { admissionAvailable.countDown(); }
        });
        try {
            synchronized (openLock.get(null)) {
                deleter.start();
                long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
                while (deleter.getState() != Thread.State.BLOCKED && System.nanoTime() < deadline) Thread.sleep(1);
                assertEquals(Thread.State.BLOCKED, deleter.getState());
                publisher.start();
                assertTrue("Delete holds the lock an opening worker needs to publish",
                        admissionAvailable.await(2, TimeUnit.SECONDS));
            }
            assertTrue(deleted.await(5, TimeUnit.SECONDS));
        } finally {
            deleter.join(5000);
            publisher.join(5000);
        }
    }

    @Test public void replacementEngineOpensWhileOldCleanupIsPending() throws Exception {
        SqflitePlugin old = engine();
        int id = open(old, "overlap.db");
        call(old, "execute", args("id", id, "sql", "CREATE TABLE data (value INTEGER)"));
        call(old, "execute", args("id", id, "sql", "INSERT INTO data VALUES (1)"));
        call(old, "execute", args("id", id, "sql", "BEGIN EXCLUSIVE", "inTransaction", true, "transactionId", null));
        Database handle = old.databaseMap.get(id);
        CountDownLatch workerPaused = new CountDownLatch(1);
        CountDownLatch releaseWorker = new CountDownLatch(1);
        handle.databaseWorkerPool.post(handle, () -> {
            workerPaused.countDown();
            try { releaseWorker.await(5, TimeUnit.SECONDS); }
            catch (InterruptedException e) { Thread.currentThread().interrupt(); }
        });
        assertTrue(workerPaused.await(5, TimeUnit.SECONDS));
        old.onDetachedFromEngine(null);
        SqflitePlugin fresh = engine();
        CountDownLatch opened = new CountDownLatch(1);
        Object[] result = new Object[1];
        String[] error = new String[1];
        try {
            fresh.onMethodCall(new MethodCall("openDatabase", args("path", handle.path)), new MethodChannel.Result() {
                public void success(Object value) { result[0] = value; opened.countDown(); }
                public void error(String code, String message, Object details) { error[0] = message; opened.countDown(); }
                public void notImplemented() { error[0] = "not implemented"; opened.countDown(); }
            });
            // The replacement is already opening before old cleanup can run.
            Thread.sleep(50);
        } finally { releaseWorker.countDown(); }
        assertTrue("Replacement waited indefinitely on old cleanup", opened.await(10, TimeUnit.SECONDS));
        assertNull(error[0], error[0]);
        int newId = (Integer) ((Map<?, ?>) result[0]).get("id");
        try {
            Map<?, ?> rows = (Map<?, ?>) call(fresh, "query", args("id", newId, "sql", "SELECT value FROM data"));
            assertEquals("[[1]]", rows.get("rows").toString());
            assertFalse(handle.sqliteDatabase.isOpen());
        } finally { call(fresh, "closeDatabase", args("id", newId)); }
    }

}
