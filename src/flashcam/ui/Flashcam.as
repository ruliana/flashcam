package flashcam.ui
{
	import mx.core.Application;
	import mx.core.FlexGlobals;
	import mx.events.FlexEvent;
	import flash.events.Event;
	import flash.events.StatusEvent;
	import flash.events.IOErrorEvent;
	import flash.events.NetStatusEvent;
	import flash.events.AsyncErrorEvent
	import flash.events.SecurityErrorEvent;
	import flash.external.ExternalInterface;
	import flash.media.Camera;
	import flash.media.H264Level;
	import flash.media.H264Profile;
	import flash.media.H264VideoStreamSettings;
	import flash.media.Microphone;
	import flash.media.Video;
	import flash.net.NetConnection;
	import flash.net.NetStream;
	import flash.system.Capabilities;

	public class Flashcam extends Application
	{	
		// software version
		private var version:String = "0.0.11";

		// server address const
		private var rtmp_server:String = "rtmp://localhost/vod";
		//private var rtmp_server:String = "rtmp://177.71.245.129:1935/vod";

		// components to show your video
		private var fileName:String = "";
		private var video:Video;
		private var display:VideoContainer;
		private var cam:Camera;
		private var mic:Microphone;
		private var stream:NetStream;
		private var connection:NetConnection;
		private var h264Settings:H264VideoStreamSettings;

		private var alreadyRecorded:Boolean = false;

		public function Flashcam()
		{
			this.addEventListener(FlexEvent.CREATION_COMPLETE, this.handleComplete);
		}

		private function handleComplete( event : FlexEvent ) : void {
			log("Flashcam (" + this.flashcamVersion() + ") created");
			logFlashPlayerType();

			init();
		}
		
		private function createVideoDisplay():void
		{
			log('Creating video display');

			this.display = new VideoContainer();
			this.display.id = "flashContent";
			this.display.width = this.width;
			this.display.height = this.height;
			this.addChild(display);
		}

		private function logFlashPlayerType():void
		{
			var flashPlayerType:String;
			
			if (Capabilities.isDebugger) flashPlayerType;
			else flashPlayerType;

			log(flashPlayerType + " " + Capabilities.playerType + " (" + Capabilities.version + ")");
		}

		private function init():void
		{
			retrieveFlashvars();
			createVideoDisplay();
			initializeCamera();
			initializeMicrophone();
			initializeConnection();
			createInterfaceCallbacks();
		}

		private function retrieveFlashvars():void
		{
			log("Retrieving flashvars");

			var params:Object = Application(FlexGlobals.topLevelApplication).parameters;

			if (params.fileName) this.fileName = params.fileName;
		}

		private function createInterfaceCallbacks():void
		{
			log("Adding ExternalInterface");
			ExternalInterface.addCallback("FC_version", this.flashcamVersion);
			ExternalInterface.addCallback("FC_recordStart", this.recordStart);
			ExternalInterface.addCallback("FC_recordStop", this.recordStop);
			ExternalInterface.addCallback("FC_recordPlayback", this.recordPlayback);
		}

		private function initializeConnection():void
		{
			this.connection = new NetConnection();
			this.connection.addEventListener(NetStatusEvent.NET_STATUS, this.netStatusHandler);
			this.connection.addEventListener(AsyncErrorEvent.ASYNC_ERROR, this.netAsyncErrorEvent);
			this.connection.addEventListener(IOErrorEvent.IO_ERROR, this.netIOErrorEvent);
			this.connection.addEventListener(SecurityErrorEvent.SECURITY_ERROR, this.netSecurityErrorEvent);

			this.connection.client = this;
			this.connection.connect(this.rtmp_server);
		}

		private function initializeCamera():void
		{
			this.video = new Video();
			this.video.opaqueBackground = true;

			this.cam = Camera.getCamera();

			if (this.cam != null)
			{
				this.configureH264();

				this.cam.setKeyFrameInterval(15);
				this.cam.setQuality(0, 90);
				this.cam.setLoopback(false);
				this.cam.addEventListener(StatusEvent.STATUS, this.statusHandler);
				this.video.attachCamera(this.cam);

				this.display.video = this.video;

				log("Camera: Bandwidth: " + this.cam.bandwidth.toString());
				log("Camera: Current FPS: " + this.cam.currentFPS.toString());
				log("Camera: FPS: " + this.cam.fps.toString());
				log("Camera: Keyframe Interval: " + this.cam.keyFrameInterval.toString());
				log("Camera: Quality: " + this.cam.quality.toString());

				ExternalInterface.call("FC_onShow");
			} else {
				log("You don't have a camera!");
			}
		}

		private function configureH264():void
		{
			log("Init H264 encoder");

			this.h264Settings = new H264VideoStreamSettings();
			this.h264Settings.setProfileLevel(H264Profile.BASELINE, H264Level.LEVEL_3);
			this.h264Settings.setKeyFrameInterval(15);
			this.h264Settings.setQuality(0, 90);
			this.h264Settings.setMode(this.video.videoWidth, this.video.videoHeight, -1);
			
			log("h264Settings: Video codec used for compression: " + this.h264Settings.codec);
			log("h264Settings: Level used for H.264/AVC encoding: " + this.h264Settings.level);
			log("h264Settings: Profile used for H.264/AVC encoding: " + this.h264Settings.profile);
			log("h264Settings: Bandwidth: " + this.h264Settings.bandwidth.toString());
			log("h264Settings: FPS: " + this.h264Settings.fps.toString());
			log("h264Settings: Keyframe interval: " + this.h264Settings.keyFrameInterval.toString());
			log("h264Settings: Quality: " + this.h264Settings.quality.toString());
		}

		private function initializeMicrophone():void
		{
			this.mic = Microphone.getMicrophone();
			this.mic.setUseEchoSuppression(true);
			this.mic.setSilenceLevel(0);

			if (this.mic != null)
			{
				this.mic.addEventListener(StatusEvent.STATUS, this.onMicStatus);

				log("Microphone plugged in!");
			} else {
				log("You don't have a microphone!");
			}
		}

		private function statusHandler(event:StatusEvent):void
		{
			trace(event.code);
			log(event.code);

			if (event.code == "Camera.Muted")
			{
				showError(4, "Access to the webcam was denied");
				return;
			} else {
				ExternalInterface.call("FC_onWebcamReady");
			}
		}
		
		private function netStatusHandler(event:NetStatusEvent):void
		{
			trace(event.info.code);
			var info:* = event.info;

			switch(info.code)
			{
				case "NetConnection.Connect.Success":
				{
					log("NetConnection connected with protocol " + this.connection.protocol + ", proxy type " + this.connection.proxyType + ", connected proxy type " + this.connection.connectedProxyType);
					ExternalInterface.call("FC_onConnect");
					break;
				}
				case "NetConnection.Connect.Closed":
				{
					ExternalInterface.call("FC_onDisconnect");
					break;
				}
				case "NetConnection.Connect.Failed":
				{
					showError(8, "Could not connect to server, check your firewall");
					break;
				}
				case "NetConnection.Connect.Rejected":
				{
					showError(1, "Unkown connection error");
					break;
				}
				case "NetStream.Play.StreamNotFound":
				{
					showError(10, "The videostream was not found");
					break;
				}
				default:
				{
					break;
				}
			}
		}

		// When streaming video or doing playback using netstream you always have to setup onMetaData
		// so this is used for both AUDIO and VIDEO
		// Where we set the netstream's client to this, it allows the netstream to automatically call this function
		public function onMetaData(info:Object):void
		{
			trace("playback called onMetaData");
		}

		private function onMicStatus(event:StatusEvent):void
		{
			if (event.code == "Microphone.Unmuted")
			{
				log("Microphone access was allowed.");
			}
			else if (event.code == "Microphone.Muted")
			{
				log("Microphone access was denied.");
			}
		}

		private function getFileName():String
		{
			var fileName:String;

			if (this.fileName) fileName = this.fileName;
			else fileName = randomNumber().toString();

			return fileName;
		}

		// video streaming
		public function recordStart():void
		{
			if (!this.connection.connected)
			{
				showError(12, "Not connected to the server");
			}

			if (this.alreadyRecorded)
			{
				showError(7, "Already recorded this file");
			} else {
				this.alreadyRecorded = true;
				this.stream = new NetStream(this.connection);
				this.stream.addEventListener(NetStatusEvent.NET_STATUS, this.netStatusHandler);
				this.stream.addEventListener(AsyncErrorEvent.ASYNC_ERROR, this.netAsyncErrorEvent);
				this.stream.addEventListener(SecurityErrorEvent.SECURITY_ERROR, this.netSecurityErrorEvent);
				this.stream.client = this;
				this.stream.videoStreamSettings = this.h264Settings;
				this.stream.attachAudio(this.mic);
				this.stream.attachCamera(this.cam);
				this.stream.publish(this.getFileName(), "record");

				this.video.attachCamera(this.cam);

				log("Recording: " + this.getFileName());
				log("Record using codec: " + this.stream.videoStreamSettings.codec);
			}
		}
		public function recordStop():void
		{
			log("Record: stop");

			this.stream.close();
			this.video.attachCamera(null);
		}

		public function recordPlayback():void
		{
			this.stream = new NetStream(this.connection);
			this.stream.addEventListener(NetStatusEvent.NET_STATUS, this.netStatusHandler);
			this.stream.addEventListener(AsyncErrorEvent.ASYNC_ERROR, this.netAsyncErrorEvent);
			this.stream.addEventListener(SecurityErrorEvent.SECURITY_ERROR, this.netSecurityErrorEvent);
			this.stream.client = this;
			this.stream.videoStreamSettings = this.h264Settings;
			this.stream.play(this.getFileName());

			this.video.attachNetStream(this.stream);
			log("Playing: " + this.getFileName());
		}

		public function onBWCheck(... args):Number
		{
			return 0;
		}

		public function onBWDone(... args):void
		{
			if (args.length > 0) args = args[0];
			Flashcam.log("Detected bandwidth: " + args + " Kbps.");
			return;
		}

		public function flashcamVersion():String
		{
			return this.version;
		}

		public static function log(text:String):void
		{
			if (ExternalInterface.available)
			{
				ExternalInterface.call("console.log", text);
			}
			return;
		}

		private static function showError(id:Number, text:String):void
		{
			log(text);

			if (ExternalInterface.available)
			{
				ExternalInterface.call("FC_onError", id, text);
			}
			return;
		}

		private function randomNumber():Number
		{
			return Math.floor(Math.random() * (9999999 - 1000000)) + 1000000;
		}

		private function netAsyncErrorEvent(event:Event):void
		{
			showError(99, "AsyncErrorEvent: " + event);
			return;
		}

		private function netSecurityErrorEvent(event:Event):void
		{
			showError(99, "netSecurityErrorEvent: " + event);
			return;
		}

		private function netIOErrorEvent(event:Event):void
		{
			showError(99, "netnetIOErrorEvent: " + event);
			return;
		}
	}
}
