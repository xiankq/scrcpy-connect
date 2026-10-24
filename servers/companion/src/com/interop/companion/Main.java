package com.interop.companion;

import android.app.Notification;
import android.app.AppOpsManager;
import android.app.KeyguardManager;
import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.ClipData;
import android.content.pm.PackageManager;
import android.content.Context;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.os.Binder;
import android.os.Build;
import android.os.Bundle;
import android.os.IBinder;
import android.os.IInterface;
import android.os.Parcel;
import android.os.Looper;
import android.os.Process;
import android.service.notification.StatusBarNotification;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

/** 临时 shell UID Binder 桥接；不安装 APK、不授予服务或 AppOp 权限、不访问数据库。 */
public final class Main {
    private static final String PACKAGE = "com.android.shell";
    private static final int MAX_LINE = 1024 * 1024;
    private static final int MAX_CLIPBOARD = (1 << 18) - 14;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final MediaJobs media = new MediaJobs(this::send);
    private final AtomicBoolean refreshPending = new AtomicBoolean();
    private final AtomicBoolean clipboardRefreshPending = new AtomicBoolean();
    private final Map<String, Item> notifications = new LinkedHashMap<>();
    private final Map<String, Item> byKey = new HashMap<>();
    private Object notificationManager, telecom, registry, notificationToken, phoneToken;
    private final CurrentUser user;
    private int callState;
    private String notificationError, callError, callId, callUiError;
    private volatile int rawPhoneState=-1;
    private final AtomicLong phoneGeneration=new AtomicLong();
    private long observedPhoneGeneration;
    private long emittedPhoneGeneration=-1;
    private int emittedCallState=-1;
    private boolean notificationsTruncated;
    private BufferedWriter output;
    private Context shellContext;
    private Object clipboard, clipboardToken;
    private boolean clipboardListening;
    private volatile boolean observationEnabled;
    private volatile long observationEpoch;
    private boolean notificationsListening, callsListening;

    Main() { this(new CurrentUser()); }
    Main(CurrentUser user) { this.user=user; }

    private static final class Item {
        StatusBarNotification sbn;
        JSONObject json;
        String fingerprint;
    }
    static final class Failure extends Exception {
        final String code;
        Failure(String code, String message) { super(message); this.code=code; }
    }
    static Object invoke(Object receiver, String name, Object... args) throws Exception {
        for (Method method : receiver.getClass().getMethods()) {
            if (!method.getName().equals(name) || method.getParameterTypes().length != args.length) continue;
            boolean compatible=true;
            Class<?>[] types=method.getParameterTypes();
            for(int i=0;i<types.length;i++) {
                if(args[i]==null) {if(types[i].isPrimitive()) compatible=false;}
                else if(!types[i].isPrimitive() && !types[i].isInstance(args[i])) compatible=false;
            }
            if(!compatible) continue;
            try { method.setAccessible(true); return method.invoke(receiver,args); }
            catch(InvocationTargetException e) {throw e.getCause() instanceof Exception ? (Exception)e.getCause() : e;}
        }
        throw new NoSuchMethodException(name+"/"+args.length);
    }
    static Object service(String name,String descriptor) throws Exception {
        Class<?> manager=Class.forName("android.os.ServiceManager");
        IBinder binder=(IBinder)manager.getMethod("getService",String.class).invoke(null,name);
        if(binder==null) throw new Failure("service_unavailable",name+" service is absent");
        return Class.forName(descriptor+"$Stub").getMethod("asInterface",IBinder.class).invoke(null,binder);
    }
    private Object callback(String descriptor,final Runnable changed) throws Exception {
        final Class<?> api=Class.forName(descriptor);
        final boolean observationCallback=!descriptor.equals("android.content.IOnPrimaryClipChangedListener");
        final long callbackEpoch=observationEpoch;
        final Set<Integer> phoneStateTransactions=new HashSet<>();
        if(descriptor.equals("com.android.internal.telephony.IPhoneStateListener")) {
            Class<?> stub=Class.forName(descriptor+"$Stub");
            for(String method:new String[]{"onCallStateChanged","onLegacyCallStateChanged"}) {
                try {Field field=stub.getDeclaredField("TRANSACTION_"+method);field.setAccessible(true);phoneStateTransactions.add(field.getInt(null));} catch(NoSuchFieldException ignored) {}
            }
        }
        final Binder binder=new Binder() {
            @Override protected boolean onTransact(int code,Parcel data,Parcel reply,int flags) {
                if(code==IBinder.INTERFACE_TRANSACTION) {if(reply!=null) reply.writeString(descriptor);return true;}
                data.enforceInterface(descriptor);
                if(observationCallback && (!observationEnabled || callbackEpoch!=observationEpoch)) {
                    if(reply!=null) reply.writeNoException();return true;
                }
                if(phoneStateTransactions.contains(code)) {
                    // 工作线程合并失效通知前，保留每次状态转换；尤其不能把 1,0,1 当成同一次已观察的响铃。
                    //
                    //
                    int state=data.readInt();
                    if(state!=rawPhoneState) {rawPhoneState=state;phoneGeneration.incrementAndGet();}
                }
                // 回调仅声明状态失效，不充当轮询计时器；新 token 对应的快照核对更新和移除，并保留 PendingIntent。
                //
                changed.run();
                if(reply!=null) reply.writeNoException();
                return true;
            }
        };
        Object token=Proxy.newProxyInstance(api.getClassLoader(),new Class<?>[]{api},(proxy,method,args)-> {
            if(method.getName().equals("asBinder")) return binder;
            if(method.getName().equals("toString")) return "InteropBinderCallback";
            if(method.getName().equals("hashCode")) return System.identityHashCode(proxy);
            if(method.getName().equals("equals")) return proxy==args[0];
            return null;
        });
        binder.attachInterface((IInterface)token,descriptor);
        return token;
    }
    private static String text(CharSequence input,int limit) {
        if(input==null) return "";
        String value=input.toString();return value.length()>limit?value.substring(0,limit):value;
    }
    private static String error(Exception e) {return e.getClass().getSimpleName()+": "+text(e.getMessage(),512);}
    private synchronized void send(JSONObject message) throws Exception {
        if(output==null) return;
        output.write(message.toString());output.write('\n');output.flush();
    }
    private void scheduleRefresh(long epoch) {
        if(!observationEnabled || epoch!=observationEpoch || !refreshPending.compareAndSet(false,true)) return;
        try {worker.execute(()-> {
            refreshPending.set(false);
            if(!observationEnabled || epoch!=observationEpoch) return;
            try {refreshNotifications(true);refreshCalls(true);} catch(Exception e) {
                try {send(new JSONObject().put("event","companion.error").put("reason",error(e)));} catch(Exception ignored) {}
            }
        });} catch(RejectedExecutionException ignored) {refreshPending.set(false);}
    }
    private void prepareContext() throws Exception {
        Object thread=Class.forName("android.app.ActivityThread").getMethod("systemMain").invoke(null);
        Context systemContext=(Context)invoke(thread,"getSystemContext");
        shellContext=systemContext.createPackageContext(PACKAGE,0);
        if(!PACKAGE.equals(shellContext.getPackageName()) || shellContext.getApplicationInfo().uid!=Process.myUid()) throw new Failure("wrong_identity","Package attribution must match the actual shell UID");
    }
    private void initialize() throws Exception {
        if(Process.myUid()!=2000) throw new Failure("wrong_identity","Companion requires the authorized ADB shell identity");
        // 共享媒体和剪贴板能力不会申请通知或电话监听。
    }
    private JSONObject observationSnapshot(boolean cleanupConfirmed) throws Exception {
        return new JSONObject().put("observationEpoch",observationEpoch).put("observationEnabled",observationEnabled)
            .put("cleanupConfirmed",cleanupConfirmed).put("notifications",notificationSnapshot()).put("calls",callSnapshot());
    }
    private JSONObject setObservation(JSONObject request) throws Exception {
        long epoch=request.getLong("epoch");boolean enabled=request.getBoolean("enabled");
        if(epoch<1 || epoch<observationEpoch) throw new Failure("stale_observation","The observation intent was replaced");
        if(enabled) user.require();
        if(epoch==observationEpoch && enabled==observationEnabled && (!notificationsListening && !callsListening || enabled)) return observationSnapshot(true);
        observationEnabled=false;observationEpoch=epoch;
        notifications.clear();byKey.clear();callId=null;callState=0;rawPhoneState=-1;
        phoneGeneration.incrementAndGet();emittedPhoneGeneration=-1;emittedCallState=-1;
        notificationsTruncated=false;notificationError=null;callError=null;callUiError=null;
        boolean clean=true;
        if(notificationsListening) {
            try {invoke(notificationManager,"unregisterListener",notificationToken,user.owner());notificationsListening=false;notificationToken=null;}
            catch(Exception e) {notificationError=error(e);clean=false;}
        }
        if(callsListening) {
            try {
                CallServices.listen(registry,phoneToken,false);
                callsListening=false;phoneToken=null;
            } catch(Exception e) {callError=error(e);clean=false;}
        }
        if(!enabled || !clean) return observationSnapshot(clean);
        user.require();
        observationEnabled=true;
        final long currentEpoch=epoch;
        try {
            notificationManager=service("notification","android.app.INotificationManager");
            notificationToken=callback("android.service.notification.INotificationListener",()->scheduleRefresh(currentEpoch));
            invoke(notificationManager,"registerListener",notificationToken,new ComponentName(PACKAGE,"com.interop.companion.Listener"),user.require());
            notificationsListening=true;refreshNotifications(false);
        } catch(Exception e) {notificationError=error(e);}
        try {
            user.require();
            telecom=service("telecom","com.android.internal.telecom.ITelecomService");
            registry=service("telephony.registry","com.android.internal.telephony.ITelephonyRegistry");
            phoneToken=callback("com.android.internal.telephony.IPhoneStateListener",()->scheduleRefresh(currentEpoch));
            CallServices.listen(registry,phoneToken,true);
            callsListening=true;refreshCalls(false);
        } catch(Exception e) {callError=error(e);}
        return observationSnapshot(true);
    }
    // 仅接受已知的 AOSP IClipboard 归因参数布局；每次调用使用实际安装的 shell 包，不伪造 android 身份。
    //
    private Object clipboardInvoke(String name,Object first) throws Exception {
        for(Method method:clipboard.getClass().getMethods()) {
            if(!method.getName().equals(name)) continue;
            Class<?>[] types=method.getParameterTypes();
            int offset=first==null?0:1;
            if(types.length<offset || (first!=null && !types[0].isInstance(first))) continue;
            int count=types.length-offset;
            boolean known=count==0 && name.equals("removePrimaryClipChangedListener")
                || count==1 && types[offset]==String.class
                || count==2 && types[offset]==String.class && types[offset+1]==int.class
                || count==3 && types[offset]==String.class && types[offset+1]==String.class && types[offset+2]==int.class
                || count==4 && types[offset]==String.class && types[offset+1]==String.class && types[offset+2]==int.class && types[offset+3]==int.class;
            if(!known) continue;
            List<Object> args=new ArrayList<>();
            if(first!=null) args.add(first);
            if(count>=1) args.add(PACKAGE);
            if(count>=3) args.add(null); // 实际 shell 没有归因标签。
            if(count>=2) args.add(user.owner());
            if(count==4) args.add(0); // 使用 Context.DEVICE_ID_DEFAULT，表示默认设备身份。
            return invoke(clipboard,name,args.toArray());
        }
        throw new Failure("clipboard_api_unavailable","Unsupported IClipboard attribution signature: "+name);
    }
    private void checkClipboardAccess(boolean writing) throws Exception {
        user.require();
        KeyguardManager keyguard=(KeyguardManager)shellContext.getSystemService(Context.KEYGUARD_SERVICE);
        if(keyguard==null) throw new Failure("clipboard_api_unavailable","Target keyguard state is unavailable");
        boolean locked=Build.VERSION.SDK_INT>=23?keyguard.isDeviceLocked():keyguard.isKeyguardLocked();
        if(locked) throw new Failure("clipboard_locked","Unlock the target device before reading or verifying its clipboard");
        if(Build.VERSION.SDK_INT>=29 && shellContext.checkCallingOrSelfPermission("android.permission.READ_CLIPBOARD_IN_BACKGROUND")!=PackageManager.PERMISSION_GRANTED)
            throw new Failure("permission_denied","The target shell package lacks background clipboard permission");
        AppOpsManager ops=(AppOpsManager)shellContext.getSystemService(Context.APP_OPS_SERVICE);
        if(ops==null || ClipboardAppOps.check(ops,writing,Process.myUid())!=AppOpsManager.MODE_ALLOWED)
            throw new Failure("permission_denied","The target denies this clipboard AppOp");
    }
    private void ensureClipboard() throws Exception {
        checkClipboardAccess(false);
        if(clipboard==null) clipboard=service("clipboard","android.content.IClipboard");
        if(!clipboardListening) {
            if(clipboardToken==null) clipboardToken=callback("android.content.IOnPrimaryClipChangedListener",this::scheduleClipboardRefresh);
            clipboardInvoke("addPrimaryClipChangedListener",clipboardToken);
            clipboardListening=true;
        }
    }
    private JSONObject clipboardGet() throws Exception {
        ensureClipboard();
        ClipData clip=(ClipData)clipboardInvoke("getPrimaryClip",null);
        checkClipboardAccess(false);
        boolean hasText=false;String value="";
        if(clip!=null && clip.getItemCount()>0) {
            CharSequence input=clip.getItemAt(0).getText();
            if(input==null) throw new Failure("clipboard_not_text","The target clipboard contains non-text content");
            value=input.toString();hasText=true;
        }
        if(value.getBytes(StandardCharsets.UTF_8).length>MAX_CLIPBOARD || JSONObject.quote(value).getBytes(StandardCharsets.UTF_8).length>MAX_LINE-1024) throw new Failure("clipboard_too_large","Clipboard text exceeds the synchronization limit");
        return new JSONObject().put("text",value).put("hasText",hasText).put("available",true).put("live",clipboardListening).put("source","companion");
    }
    private JSONObject clipboardSet(JSONObject request) throws Exception {
        String value=request.getString("text");
        if(value.getBytes(StandardCharsets.UTF_8).length>MAX_CLIPBOARD || JSONObject.quote(value).getBytes(StandardCharsets.UTF_8).length>MAX_LINE-1024) throw new Failure("invalid_argument","Clipboard text exceeds the synchronization limit");
        ensureClipboard();checkClipboardAccess(true);
        clipboardInvoke("setPrimaryClip",ClipData.newPlainText("跨设备互联",value));
        JSONObject verified=clipboardGet();
        if(!verified.getBoolean("hasText") || !value.equals(verified.getString("text"))) throw new Failure("clipboard_not_applied","The target clipboard changed or did not accept the requested text");
        return new JSONObject().put("applied",true).put("source","companion");
    }
    private void scheduleClipboardRefresh() {
        if(!clipboardRefreshPending.compareAndSet(false,true)) return;
        try {worker.execute(()-> {
            clipboardRefreshPending.set(false);
            try {send(new JSONObject().put("event","clipboard.changed").put("data",clipboardGet()));}
            catch(Exception e) {
                try {send(new JSONObject().put("event","clipboard.unavailable").put("data",new JSONObject().put("available",false).put("live",false).put("reason",error(e))));} catch(Exception ignored) {}
            }
        });} catch(RejectedExecutionException ignored) {clipboardRefreshPending.set(false);}
    }
    private String notificationAppName(StatusBarNotification notification) {
        try {
            // 在实际用户配置中解析原始包；通知 extras 中的替代标签不代表应用身份。
            //
            Class<?> handle=Class.forName("android.os.UserHandle");
            Object user=handle.getConstructor(int.class).newInstance(notification.getUserId());
            Context application=(Context)Context.class.getMethod("createPackageContextAsUser",String.class,int.class,handle)
                .invoke(shellContext,notification.getPackageName(),0,user);
            CharSequence label=application.getPackageManager().getApplicationLabel(application.getApplicationInfo());
            String name=text(label,512).trim();
            if(!name.isEmpty() && !name.equals(notification.getPackageName())) return name;
        } catch(Exception unavailable) {
            // 元数据读取失败不应让原本可操作的内容失效。
        }
        return "手机通知";
    }
    private void refreshNotifications(boolean event) throws Exception {
        if(!observationEnabled || !notificationsListening || notificationError!=null) return;
        user.require();
        Object slice=invoke(notificationManager,"getActiveNotificationsFromListener",notificationToken,null,0);
        @SuppressWarnings("unchecked") List<StatusBarNotification> current=(List<StatusBarNotification>)invoke(slice,"getList");
        Map<String,Item> next=new LinkedHashMap<>();Map<String,Item> keys=new HashMap<>();
        int snapshotBytes=0;notificationsTruncated=false;
        for(StatusBarNotification sbn:current) {
            if(next.size()>=1000) {notificationsTruncated=true;break;}
            Notification n=sbn.getNotification();Bundle extras=n.extras;
            JSONObject data=new JSONObject().put("key",sbn.getKey()).put("packageName",sbn.getPackageName())
                .put("appName",notificationAppName(sbn)).put("userId",sbn.getUserId()).put("uid",sbn.getUid())
                .put("title",NotificationContent.title(extras))
                .put("body",NotificationContent.body(extras))
                .put("postedAt",sbn.getPostTime()).put("canOpen",n.contentIntent!=null)
                .put("groupSummary",(n.flags & Notification.FLAG_GROUP_SUMMARY)!=0)
                .put("canDismiss",sbn.isClearable());
            StringBuilder fingerprint=new StringBuilder(data.toString());
            fingerprint.append(n.contentIntent==null?0:n.contentIntent.hashCode());
            Item old=byKey.get(sbn.getKey());Item item=new Item();item.sbn=sbn;item.fingerprint=fingerprint.toString();
            String id=old!=null && old.fingerprint.equals(item.fingerprint)?old.json.getString("id"):UUID.randomUUID().toString();
            item.json=data.put("id",id).put("revision",id);
            snapshotBytes+=item.json.toString().getBytes(StandardCharsets.UTF_8).length;
            if(snapshotBytes>768*1024) {notificationsTruncated=true;break;}
            next.put(id,item);keys.put(sbn.getKey(),item);
        }
        user.require();
        String before=notificationList().toString();notifications.clear();notifications.putAll(next);byKey.clear();byKey.putAll(keys);
        if(event && !before.equals(notificationList().toString())) send(new JSONObject().put("event","notifications.changed").put("data",notificationSnapshot()));
    }
    private JSONArray notificationList() {JSONArray result=new JSONArray();for(Item item:notifications.values()) result.put(item.json);return result;}
    private JSONObject notificationSnapshot() throws Exception {
        if(!observationEnabled) return new JSONObject().put("notifications",new JSONArray()).put("status",notificationError==null?"stopped":"unknown").put("live",false).put("reason",notificationError==null?"通知与来电观察已停止。":notificationError).put("observationEpoch",observationEpoch).put("observationEnabled",false);
        user.require();
        return new JSONObject().put("observationEpoch",observationEpoch).put("observationEnabled",true).put("notifications",notificationList()).put("status",notificationError==null && !notificationsTruncated?"available":"limited")
            .put("reason",notificationError!=null?notificationError:notificationsTruncated?"部分通知未同步，请进入手机查看。":JSONObject.NULL)
            .put("truncated",notificationsTruncated).put("live",notificationError==null).put("userId",user.owner());
    }
    private boolean keyguardLocked() throws Exception {
        return (Boolean)invoke(service("window","android.view.IWindowManager"),"isKeyguardLocked");
    }
    private JSONObject notificationAction(String command,JSONObject request) throws Exception {
        user.require();
        if(!observationEnabled || !notificationsListening) throw new Failure("observation_required","Start notification observation before using its actions");
        if(notificationError!=null) throw new Failure("permission_or_api_unavailable",notificationError);
        refreshNotifications(false);
        Item item=notifications.get(request.getString("notificationId"));
        if(item==null) throw new Failure("notification_expired","The original notification changed or was removed; refresh before acting");
        Notification notification=item.sbn.getNotification();
        if(command.equals("notifications.dismiss")) {
            if(!item.sbn.isClearable()) throw new Failure("not_dismissible","Android marks this notification as ongoing");
            user.require();
            invoke(notificationManager,"cancelNotificationsFromListener",notificationToken,new String[]{item.sbn.getKey()});
            refreshNotifications(true);
            return new JSONObject().put("acceptedBySystem",true).put("dismissed",!byKey.containsKey(item.sbn.getKey())).put("markedRead",false);
        }
        if(keyguardLocked()) throw new Failure("authentication_required","Unlock the target device before continuing this notification action");
        if(command.equals("notifications.open")) {
            if(notification.contentIntent==null) throw new Failure("no_original_action","The original notification has no content PendingIntent");
            user.require();
            notification.contentIntent.send(shellContext,0,null);
            return new JSONObject().put("acceptedBySystem",true).put("located",true).put("requiresRemoteView",true).put("applicationConfirmed",false);
        }
        throw new Failure("invalid_command","Unknown notification action");
    }
    private void refreshCalls(boolean event) throws Exception {
        if(!observationEnabled || !callsListening || callError!=null) return;
        user.require();
        int previous=callState;int actual=CallServices.state(telecom);
        user.require();
        long generation=phoneGeneration.get();
        if(actual!=0 && (callId==null || generation!=observedPhoneGeneration)) callId=UUID.randomUUID().toString();
        observedPhoneGeneration=generation;
        if(actual==0) callId=null;
        callState=actual;
        if(event && (emittedCallState!=actual || emittedPhoneGeneration!=generation)) {
            emittedCallState=actual;emittedPhoneGeneration=generation;
            send(new JSONObject().put("event",actual==1?"calls.incoming":"calls.changed").put("data",callSnapshot()));
        }
    }
    private JSONObject callSnapshot() throws Exception {
        if(!observationEnabled) return new JSONObject().put("calls",new JSONArray()).put("status",callError==null?"stopped":"unknown").put("live",false).put("reason",callError==null?"通知与来电观察已停止。":callError).put("audioStatus","unknown").put("observationEpoch",observationEpoch).put("observationEnabled",false);
        user.require();
        JSONArray calls=new JSONArray();
        if(callState!=0 && callError==null) calls.put(new JSONObject().put("id",callId).put("state",callState==1?"ringing":"active")
            .put("name","当前系统通话").put("canAnswer",false).put("canReject",false)
            .put("canHangup",false).put("canSetRoute",false).put("aggregate",true).put("generation",observedPhoneGeneration));
        boolean uiApiAvailable=systemCallUiMethod()!=null;
        return new JSONObject().put("observationEpoch",observationEpoch).put("observationEnabled",true).put("calls",calls).put("status","limited").put("controlStatus","limited").put("live",callError==null)
            .put("canOpenSystemCallUi",callError==null && callsListening && callState!=0 && uiApiAvailable && callUiError==null)
            .put("canRetrySystemCallUi",callError==null && callsListening && callState!=0 && uiApiAvailable && callUiError!=null)
            .put("systemCallUiStatus",callUiError!=null?"limited":telecom==null?"unknown":uiApiAvailable?"available":"unsupported")
            .put("systemCallUiReason",callUiError!=null?"打开系统通话界面失败："+callUiError+"。可重试打开，或在手机上继续处理。":!uiApiAvailable?"此系统未提供已适配的通话界面打开接口。":"仅请求打开手机当前系统通话界面，不定位或控制某一通电话；界面是否出现需在远控画面确认。")
            .put("reason",callError==null?"当前只能同步系统聚合通话状态；具体通话的安全定位尚未完成，请在手机原电话应用接听或挂断。多SIM、通话等待与第三方VoIP仍待验证。":callError)
            .put("audioStatus","unknown").put("audioRoute","声音与麦克风继续由被控手机处理；主控双向通话音频尚未实现。");
    }
    private Method systemCallUiMethod() {
        return CallServices.systemUiMethod(telecom);
    }
    private JSONObject openSystemCallUi(JSONObject request) throws Exception {
        if(request.has("callId")) throw new Failure("call_targeting_unavailable","此入口仅打开手机当前系统通话界面，不能定位指定通话。");
        if(!observationEnabled || !callsListening || callError!=null) throw new Failure("observation_required","请先核验此设备的实时通话状态。");
        refreshCalls(false);
        if(callState==0) throw new Failure("no_current_call","手机当前已没有系统通话，请重新核验通话状态。");
        user.require();
        Method method=systemCallUiMethod();
        if(method==null) throw new Failure("call_ui_unsupported","此系统未提供已适配的通话界面打开接口，请在手机上继续处理。");
        try {
            CallServices.openSystemUi(telecom);
        } catch(Exception e) {
            Exception cause=e instanceof InvocationTargetException && e.getCause() instanceof Exception?(Exception)e.getCause():e;
            callUiError=error(cause);
            throw new Failure(cause instanceof SecurityException?"permission_denied":"call_ui_unavailable","手机未接受打开系统通话界面的请求："+callUiError);
        }
        callUiError=null;
        return new JSONObject().put("target","currentSystemCall").put("status","acceptedBySystem")
            .put("acceptedBySystem",true).put("uiVisible",JSONObject.NULL).put("callControlled",false)
            .put("message","系统已接受打开当前通话界面的请求；请在远控画面确认，不代表接听或挂断了通话。");
    }
    private JSONObject callAction(JSONObject request) throws Exception {
        // Telecom 的聚合 endCall/acceptRingingCall 没有通话对象；即使刚检查过状态，两次 Binder 事务之间仍可能更换通话，观察 UUID 无法保障此类操作安全。
        //
        //
        throw new Failure("call_targeting_unavailable","具体通话的安全定位尚未完成，未执行任何接听或挂断；请在手机原电话应用处理。");
    }
    private JSONObject execute(JSONObject request) throws Exception {
        String command=request.getString("command");
        if(command.equals("observation.set")) return setObservation(request);
        if(command.equals("notifications.list")) {refreshNotifications(false);return notificationSnapshot();}
        if(command.equals("notifications.open") || command.equals("notifications.dismiss")) return notificationAction(command,request);
        if(command.equals("calls.list")) {refreshCalls(false);return callSnapshot();}
        if(command.equals("calls.open")) return openSystemCallUi(request);
        if(command.equals("calls.action")) return callAction(request);
        if(command.equals("clipboard.get")) return clipboardGet();
        if(command.equals("clipboard.set")) return clipboardSet(request);
        if(command.equals("apps.list")) {
            try {JSONObject result=Apps.running(shellContext,user.require());user.require();return result;}
            catch(NoSuchMethodException | NoSuchFieldException unavailable) {throw new Failure("apps_running_unavailable","Verified application task metadata is unavailable on this device");}
        }
        if(command.equals("apps.icon")) {JSONObject result=Apps.icon(shellContext,request,user.require());user.require();return result;}
        throw new Failure("invalid_command","Unknown companion command");
    }
    private static String readLine(InputStream input) throws Exception {
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();
        for(int b;(b=input.read())!=-1;) {if(b=='\n') return new String(bytes.toByteArray(),StandardCharsets.UTF_8);if(bytes.size()>=MAX_LINE) throw new Failure("input_limit","Companion request too large");bytes.write(b);}
        return bytes.size()==0?null:new String(bytes.toByteArray(),StandardCharsets.UTF_8);
    }
    private void run(String socketName,String secret) throws Exception {
        LocalServerSocket server=new LocalServerSocket(socketName);
        ScheduledExecutorService watchdog=Executors.newSingleThreadScheduledExecutor();
        Future<?> startupDeadline=watchdog.schedule(()-> {try {server.close();}catch(Exception ignored){}},20,TimeUnit.SECONDS);
        // 这是唯一的 stdout 协议；通知正文仅通过已认证的内存本地 socket 传送。
        //
        System.out.println("INTEROP_COMPANION_READY "+Process.myPid());System.out.flush();
        try(LocalSocket socket=server.accept()) {
            socket.setSoTimeout(15000);InputStream input=new BufferedInputStream(socket.getInputStream());
            String auth=readLine(input);
            if(auth==null || !secret.equals(new JSONObject(auth).optString("token"))) throw new Failure("unauthorized","Companion socket authentication failed");
            startupDeadline.cancel(false);watchdog.shutdownNow();
            socket.setSoTimeout(0);output=new BufferedWriter(new OutputStreamWriter(socket.getOutputStream(),StandardCharsets.UTF_8));
            JSONObject ready=worker.submit(()-> {
                initialize();
                return new JSONObject().put("event","ready").put("protocol",1).put("uid",Process.myUid()).put("apiLevel",Build.VERSION.SDK_INT)
                    .put("notifications",notificationSnapshot()).put("calls",callSnapshot());
            }).get();send(ready);
            for(String line;(line=readLine(input))!=null;) {
                final JSONObject request=new JSONObject(line);
                if (request.optString("command").startsWith("media.")) { media.accept(request); continue; }
                worker.submit(()-> {
                    JSONObject response=new JSONObject().put("requestId",request.getString("requestId"));
                    try {response.put("result",execute(request));}
                    catch(Exception e) {String code=e instanceof Failure?((Failure)e).code:e instanceof PendingIntent.CanceledException?"notification_expired":e instanceof SecurityException?"permission_denied":"companion_error";response.put("error",new JSONObject().put("code",code).put("message",error(e)));}
                    send(response);return null;
                }).get();
            }
        } finally {
            media.close();
            try {if(clipboardListening) clipboardInvoke("removePrimaryClipChangedListener",clipboardToken);} catch(Exception ignored) {}
            try {setObservation(new JSONObject().put("enabled",false).put("epoch",observationEpoch+1));} catch(Exception ignored) {}
            watchdog.shutdownNow();worker.shutdownNow();server.close();
        }
    }
    public static void main(String[] args) {
        try {
            // 遵循固定上游 scrcpy 服务端：debug/eng adbd 可能以 root 启动 app_process，但协同操作始终使用 shell；创建上下文、访问 Binder 或创建线程前先降权，失败立即终止，不执行特权工作。
            //
            //
            //
            if(Process.myUid()==0) android.system.Os.setuid(2000);
            if(Process.myUid()!=2000) throw new Failure("wrong_identity","Companion requires the authorized ADB shell identity");
            if(args.length!=2 || !args[0].matches("interop-companion-[0-9a-f]{32}") || !args[1].matches("[0-9a-f]{64}")) throw new Failure("invalid_argument","Expected a random abstract socket name and authentication token");
            Looper.prepareMainLooper();
            Main main=new Main();main.prepareContext();main.run(args[0],args[1]);System.exit(0);
        } catch(Exception e) {
            Exception cause=e.getCause() instanceof Exception?(Exception)e.getCause():e;
            System.err.println("INTEROP_COMPANION_ERROR "+error(cause));System.exit(1);
        }
    }
}
