package com.saltechsystems.couchbase_lite;

import androidx.annotation.NonNull;

import com.couchbase.lite.CouchbaseLiteException;
import com.couchbase.lite.ReplicatorChange;
import com.couchbase.lite.ReplicatorChangeListener;

import io.flutter.plugin.common.EventChannel;

public class ReplicationEventListener implements EventChannel.StreamHandler, ReplicatorChangeListener {
    public EventChannel.EventSink mEventSink;

    /*
     * IMPLEMENTATION OF EVENTCHANNEL.STREAMHANDLER
     */
    @Override
    public void onListen(Object o, final EventChannel.EventSink eventSink) {
        mEventSink = eventSink;
    }

    @Override
    public void onCancel(Object o) {
        mEventSink = null;
    }

    /*
     *  IMPLEMENTATION OF REPLICATORCHANGELISTENER INTERFACE
     */

    @Override
    public void changed(@NonNull ReplicatorChange change) {
        if (mEventSink == null) {
            return;
        }

        CouchbaseLiteException error = change.getStatus().getError();
        if (error != null) {
            mEventSink.error("CouchbaseLiteException", "Error during replication", error.getCode());
        } else {
            switch (change.getStatus().getActivityLevel()) {
                case BUSY:
                    mEventSink.success("BUSY");
                    break;
                case IDLE:
                    mEventSink.success("IDLE");
                    break;
                case OFFLINE:
                    mEventSink.success("OFFLINE");
                    break;
                case STOPPED:
                    mEventSink.success("STOPPED");
                    break;
                case CONNECTING:
                    mEventSink.success("CONNECTING");
                    break;
            }
        }
    }
}
