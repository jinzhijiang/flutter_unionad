import {
  AbilityAware, AbilityPluginBinding, Any, FlutterPlugin, FlutterPluginBinding, MethodCall, MethodCallHandler, MethodChannel, MethodResult,
} from '@ohos/flutter_ohos';
import {
  AdLoadType, AdSlotBuilder, CSJAdCreator, CSJAdSdk, CSJRewardAd, RewardAdInteractionListener, RewardAdLoadListener, SDKConfig, SDKConfigBuilder, MediationConfigBuilder
} from '@csj/openadsdk';
import { UIAbility } from '@kit.AbilityKit';
import FlutterUnionadEventPlugin from './FlutterUnionadEventPlugin';
import FullScreenVideoAdInteraction from './FullScreenVideoAdInteraction';
import FlutterUnionadViewPlugin from './FlutterUnionadViewPlugin';

/** FlutterUnionadPlugin **/
export default class FlutterUnionadPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private applicationContext: Context | null = null;
  private uiAbility: UIAbility | null = null;
  // Official docs: call getAdCreator only after CSJAdSdk.start succeeds.
  // Creating it at field init (before init/start) can keep mediation off → 40006.
  private adCreator: CSJAdCreator | null = null;
  private rewardAd: CSJRewardAd | null = null;
  private flutterPluginBinding: FlutterPluginBinding | null = null;

  constructor() {
  }

  getUniqueClassName(): string {
    return "FlutterUnionadPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    console.log("FlutterUnionadPlugin onAttachedToEngine")
    this.flutterPluginBinding = binding;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "flutter_unionad");
    this.channel.setMethodCallHandler(this)
    this.applicationContext = binding.getApplicationContext();
    new FlutterUnionadEventPlugin().onAttachedToEngine(binding);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }

    this.flutterPluginBinding = null
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    console.log("FlutterUnionadPlugin onAttachedToAbility")
    this.uiAbility = binding.getAbility()
    if(this.flutterPluginBinding){
      FlutterUnionadViewPlugin.register(this.flutterPluginBinding, this.uiAbility)
    }
  }

  onDetachedFromAbility(): void {
    this.uiAbility = null
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method == "register") {
      let appId: string = call.args.get("appId");
      let appName: string = call.args.get("appName");
      let debug: boolean = call.args.get("debug");
      let useMediation: boolean = call.args.get("useMediation");
      // 创建SDKConfig对象
      let adConfigBuilder = new SDKConfigBuilder()
      let config: SDKConfig = adConfigBuilder
        .appId(appId)
        .appName(appName)
        .allowShowNotify(true)
        .debug(debug)
        // 是否开启聚合功能  true:开启  false:不开启
        .setMediationConfig(
          new MediationConfigBuilder()
            .useMediation(useMediation)
            .build()
        )
        .build()

      // 初始化SDK
      CSJAdSdk.init(this.uiAbility?.context, config) //context类型必须为UIAbility，否则可能存在展示异常场景

      // 启动SDK；官方要求等 start 成功（0 / 4200）后再 getAdCreator / 请求广告
      CSJAdSdk.start().then((startResult) => {
        const code = startResult?.code
        const ok = code == 0 || code == 4200
        if (ok) {
          this.adCreator = CSJAdSdk.getAdCreator()
        }
        result.success(ok)
      }).catch((e: Error) => {
        console.error(`FlutterUnionadPlugin start failed: ${e}`)
        result.success(false)
      })
    } else if (call.method == "getSDKVersion") {
      result.success(CSJAdSdk.getSDKVersion())
    } else if (call.method == "getThemeStatus") {
      //todo 没做
      result.success(0)
    } else if (call.method == "loadRewardVideoAd") {
      let codeId: string = call.args.get("codeId");
      let userID: string = call.args.get("userID") ?? "";
      let mediaExtra: string = call.args.get("mediaExtra") ?? "";
      let rewardName: string = call.args.get("rewardName") ?? "";
      let rewardAmount: number = call.args.get("rewardAmount") ?? 0;
      if (this.adCreator == null) {
        this.adCreator = CSJAdSdk.getAdCreator()
      }
      // 鸿蒙 SDK 的 AdSlotBuilder 没有 setUserID，服务端奖励回调只带 mediaExtra（回调参数 extra），
      // 且只支持单层 JSON 对象，所以把用户 id 和业务透传值一起放进去，由服务端从 extra 里取。
      let extra: Record<string, string> = {
        "user_id": userID,
        "media_extra": mediaExtra,
      }
      let slotBuilder = new AdSlotBuilder()
        .setCodeId(codeId)
        .setAdLoadType(AdLoadType.LOAD)
        .setMediaExtra(JSON.stringify(extra))
      if (rewardName.length > 0) {
        slotBuilder.setRewardName(rewardName)
      }
      if (rewardAmount > 0) {
        slotBuilder.setRewardAmount(rewardAmount)
      }
      let adSlot = slotBuilder.build()
      // 重新加载前丢掉上一条，避免新广告还没回来时把旧实例再展示一次
      this.rewardAd = null
      let mLoadListener: RewardAdLoadListener = {
        onAdLoaded: (rewardAd: CSJRewardAd) => {
          console.error("rewardVideoAd loaded 广告类型：${getAdType(ad.rewardVideoAdType)}")
          this.rewardAd = rewardAd;
          FlutterUnionadEventPlugin.sendContent(
            new Map([["adType", "rewardAd"], ["onAdMethod", "onReady"]])
          );
        },
        onAdCached: (rewardAd: CSJRewardAd) => {
          console.error("rewardVideoAd video cached2")
          let map: Record<string, Any> = {
            "adType": "rewardAd", "onAdMethod": "onCache"
          };
          FlutterUnionadEventPlugin.sendContent(map)
        },
        onError: (code: number, message: string) => {
          console.error("视频加载失败" + code + message);
          let map: Record<string, Any> = {
            "adType": "rewardAd", "onAdMethod": "onFail", "error": code + message
          };
          FlutterUnionadEventPlugin.sendContent(map);
        }
      }
      this.adCreator!.loadRewardAd(adSlot, mLoadListener)
      result.success(true)
    } else if (call.method == "showRewardVideoAd") {
      let adInteractionListener: RewardAdInteractionListener = {
        onShow: () => {
          console.error("rewardVideoAd show")
          let map: Record<string, Any> = {
            "adType": "rewardAd", "onAdMethod": "onShow"
          };
          FlutterUnionadEventPlugin.sendContent(map)
        },
        onSkip: () => {
          console.error("rewardVideoAd onSkippedVideo")
          let map: Record<string, Any> = {
            "adType": "rewardAd", "onAdMethod": "onSkip"
          };
          FlutterUnionadEventPlugin.sendContent(map)
        },
        onClick: () => {
          console.error("rewardVideoAd bar click")
          let map: Record<string, Any> = {
            "adType": "rewardAd", "onAdMethod": "onClick"
          };
          FlutterUnionadEventPlugin.sendContent(map)
        },
        onComplete: () => {
          console.error("rewardVideoAd complete")
        },
        onClose: () => {
          console.error("rewardVideoAd close")
          let map: Record<string, Any> = {
            "adType": "rewardAd", "onAdMethod": "onClose"
          };
          FlutterUnionadEventPlugin.sendContent(map)
        },
        onRewardArrived: (isVerify, rewardType, extraInfo) => {
          console.error("verify: $p0 amount:$p1 name:$p2 p3:$p3 p4:$p4")
          let map: Record<string, Any> = {
            "adType": "rewardAd",
            "onAdMethod": "onVerify",
            "rewardVerify": isVerify,
            "rewardAmount": 0,
            "rewardName": "0",
            "errorCode": 0,
            "error": "",
          };

          FlutterUnionadEventPlugin.sendContent(map)
        }
      }
      // 广告基础信息加载完成x
      const readyAd = this.rewardAd
      if (readyAd != null && this.uiAbility != null) {
        // 一条广告只展示一次
        this.rewardAd = null
        readyAd.setInteractionListener(adInteractionListener)
        readyAd.showRewardAd(this.uiAbility.context.windowStage)
      } else {
        let map: Record<string, Any> = {
          "adType": "rewardAd", "onAdMethod": "onUnReady", "error": "广告预加载未完成"
        };
        FlutterUnionadEventPlugin.sendContent(map)
      }
      result.success(true)
    } else if (call.method == "loadFullScreenVideoAdInteraction") {
      let codeId: string = call.args.get("codeId");
      let orientation: number = call.args.get("orientation");
      FullScreenVideoAdInteraction.init(
        this.applicationContext!,
        this.uiAbility!.context.windowStage,
        codeId,
        orientation!!,
      )
      result.success(true)
      //显示插屏广告 全屏插屏二合一
    } else if (call.method == "showFullScreenVideoAdInteraction") {
      FullScreenVideoAdInteraction.showAd()
      result.success(true)
    } else {
      result.notImplemented()
    }
  }
}
