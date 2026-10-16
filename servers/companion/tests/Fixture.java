package com.interop.companion;

import android.app.*;
import android.content.*;
import android.os.*;
import android.provider.Settings;
import org.json.JSONObject;
import java.io.*;
import java.lang.reflect.*;
import java.util.*;

/** Test-only real notifications/PendingIntents/RemoteInput; never included in companion.jar. */
public final class Fixture {
    public static void main(String[] args) throws Exception {
        String tag="interop-fixture-"+UUID.randomUUID();String action=tag+".REPLY";
        Looper.prepareMainLooper();
        Object thread=Class.forName("android.app.ActivityThread").getMethod("systemMain").invoke(null);
        Context system=(Context)Main.invoke(thread,"getSystemContext");
        Context context=system.createPackageContext("com.android.shell",0);
        Object manager=Main.service("notification","android.app.INotificationManager");
        Object activity=Main.service("activity","android.app.IActivityManager");
        Class<?> receiverApi=Class.forName("android.content.IIntentReceiver");
        Binder binder=new Binder() {
            @Override protected boolean onTransact(int code,Parcel data,Parcel reply,int flags) {
                if(code==INTERFACE_TRANSACTION) {if(reply!=null) reply.writeString("android.content.IIntentReceiver");return true;}
                data.enforceInterface("android.content.IIntentReceiver");
                Intent intent=data.readInt()!=0?Intent.CREATOR.createFromParcel(data):null;
                Bundle results=intent==null?null:RemoteInput.getResultsFromIntent(intent);
                try {System.out.println(new JSONObject().put("event","reply.received").put("text",results==null?JSONObject.NULL:results.getCharSequence("original-result-key")));System.out.flush();} catch(Exception e) {throw new RuntimeException(e);}
                if(reply!=null) reply.writeNoException();return true;
            }
        };
        Object receiver=Proxy.newProxyInstance(receiverApi.getClassLoader(),new Class<?>[]{receiverApi},(proxy,method,values)->method.getName().equals("asBinder")?binder:null);
        binder.attachInterface((IInterface)receiver,"android.content.IIntentReceiver");
        Main.invoke(activity,"registerReceiverWithFeature",null,"com.android.shell",null,tag,receiver,new IntentFilter(action),null,0,Context.RECEIVER_EXPORTED);
        Object channelSlice=Class.forName("android.content.pm.ParceledListSlice").getConstructor(List.class)
            .newInstance(Collections.singletonList(new NotificationChannel(tag,"Interop temporary E2E",NotificationManager.IMPORTANCE_DEFAULT)));
        Main.invoke(manager,"createNotificationChannels","com.android.shell",channelSlice);
        // A Binder receiver registered without an ApplicationThread has no
        // installed process package filter. The random action names this test
        // receiver without pretending the shell JAR is an installed APK.
        PendingIntent reply=PendingIntent.getBroadcast(context,1,new Intent(action),PendingIntent.FLAG_MUTABLE|PendingIntent.FLAG_ALLOW_UNSAFE_IMPLICIT_INTENT|PendingIntent.FLAG_UPDATE_CURRENT);
        PendingIntent immutable=PendingIntent.getBroadcast(context,2,new Intent(action),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
        PendingIntent open=PendingIntent.getActivity(context,3,new Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
        PendingIntent cancelled=PendingIntent.getActivity(context,4,new Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
        RemoteInput input=new RemoteInput.Builder("original-result-key").setLabel("Reply").build();
        try {
            for(int i=0;i<4;i++) {
                Notification.Builder builder=new Notification.Builder(context,tag).setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentTitle(tag+"-"+i).setContentText("Synthetic interoperability fixture").setContentIntent(i==3?cancelled:open);
                if(i<3) {
                    Notification.Action.Builder original=new Notification.Action.Builder(null,"Reply",i==1?immutable:reply).setAuthenticationRequired(i==2);
                    // Android 16 rejects posting RemoteInput + immutable PI at
                    // the notification service boundary. An immutable action
                    // without RemoteInput remains a valid negative fixture.
                    if(i!=1) original.addRemoteInput(input);
                    builder.addAction(original.build());
                }
                Main.invoke(manager,"enqueueNotificationWithTag","com.android.shell","com.android.shell",tag,i,builder.build(),0);
            }
            cancelled.cancel();
            System.out.println(new JSONObject().put("event","fixture.ready").put("tag",tag));System.out.flush();
            new BufferedReader(new InputStreamReader(System.in)).readLine();
        } finally {
            for(int i=0;i<4;i++) Main.invoke(manager,"cancelNotificationWithTag","com.android.shell","com.android.shell",tag,i,0);
            Main.invoke(manager,"deleteNotificationChannel","com.android.shell",tag);
            Main.invoke(activity,"unregisterReceiver",receiver);reply.cancel();immutable.cancel();open.cancel();
        }
        System.exit(0);
    }
}
