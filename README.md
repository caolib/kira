<h1 align="center">
<img src="https://files.seeusercontent.com/2026/04/09/hOy5/logo.png"/>
</h1>

<p align="center">
  <img src="https://skills.syvixor.com/api/icons?perline=15&i=flutter,dart,materialdesign"/>
</p>

<p align="center">
  <img alt="GitHub License" src="https://img.shields.io/github/license/caolib/kira">
  <img alt="GitHub Issues or Pull Requests" src="https://img.shields.io/github/issues/caolib/kira">
  <img src="https://img.shields.io/github/stars/caolib/kira" alt="Stars"/>
  <img src="https://img.shields.io/github/downloads/caolib/kira/latest/total" alt="Latest Downloads"/>
  <a href="https://qm.qq.com/q/rezw7xWuK4"><img src="https://img.shields.io/badge/%E4%BA%A4%E6%B5%81%E7%BE%A4-white?logo=QQ" alt="QQ Group"/></a>

</p>

## 简介

一个热辣漫画的第三方客户端 | A third-party client based on hotmanga

<table>
  <tr>
    <td><img src="https://files.seeusercontent.com/2026/06/24/9Dus/image-20260624215216838.png"/></td>
    <td><img src="https://files.seeusercontent.com/2026/06/25/p8Bl/image-20260625153000227.png"/></td>
  </tr> 
  <tr>
    <td><img src="https://files.seeusercontent.com/2026/06/25/dMh5/20260625153111865.png"/></td>
    <td><img src="https://files.seeusercontent.com/2026/06/25/lL6u/20260625153045529.png"/></td>
  </tr>
</table>


<details>
<summary>查看更多截图</summary>
<table>
  <tr>
    <td><img src="https://files.seeusercontent.com/2026/05/14/6guP/PixPin_2026-05-14_15-55-21.png"/></td>
    <td><img src="https://files.seeusercontent.com/2026/05/14/oK3h/PixPin_2026-05-14_15-56-28.png"/></td>
  </tr>
  <tr>
    <td><img src="https://files.seeusercontent.com/2026/05/14/fEm5/PixPin_2026-05-14_16-02-05.png"/></td>
    <td><img src="https://files.seeusercontent.com/2026/05/14/I1sh/PixPin_2026-05-14_15-53-03.png"/></td>
  </tr>
  <tr>
    <td><img src="https://files.seeusercontent.com/2026/05/14/gW8m/PixPin_2026-05-14_16-00-34.png"/></td>
    <td><img src="https://files.seeusercontent.com/2026/05/14/7efA/PixPin_2026-05-14_16-11-06.png"/></td>
  </tr>
</table>
</details>

## 开发

### 环境要求

- Dart
- Flutter
- Java 17

### 初始化项目

```sh
git clone https://github.com/caolib/kira.git
cd kira
```

国内环境可以设置flutter镜像，设置环境变量`PUB_HOSTED_URL=https://pub.flutter-io.cn`，然后拉取依赖

```sh
flutter pub get
```

### 运行项目

如果你需要弹幕功能，需要先创建弹弹play账号，获取`appId`和`appSecret`，然后在项目根目录下创建一个`.env`文件，内容参考`.env.example`

查看可用设备

```sh
flutter devices
```

如果你本地有Android Studio的虚拟机，可以使用下面命令列出并启动它

```sh
flutter emulators

flutter emulators --launch 设备ID
```

启动项目，选择安卓设备（包括模拟器）或windows都可以，不要选择浏览器

```sh
flutter run -d 设备ID --dart-define-from-file=.env
```

### 构建安装包

在本地构建apk安装包，需要在项目根目录下创建一个`.env`文件（内容参考`.env.example`，如果不需要弹幕功能可以不创建这个文件）

```sh
flutter build apk --release --target-platform android-arm64 --dart-define-from-file=.env
```

## 致谢

感谢以下服务支持：

- [弹弹play](https://www.dandanplay.com/) — 提供弹幕服务
- [繁化姬](https://zhconvert.org/) — 提供简体化服务

本项目基于以下优秀的开源库构建：

- [dio](https://github.com/cfug/dio) - 网络请求
- [cached_network_image](https://github.com/Baseflow/flutter_cached_network_image) - 图片缓存加载
- [media_kit](https://github.com/media-kit/media-kit) - 视频播放
- [canvas_danmaku](https://github.com/Predidit/canvas_danmaku) - 弹幕渲染
- [flutter_svg](https://github.com/dnfield/flutter_svg) - SVG 图标支持
- [flex_color_picker](https://github.com/rydmike/flex_color_picker) - 颜色选择器
- [scrollable_positioned_list](https://github.com/google/flutter.widgets) - 漫画翻页定位
- [shared_preferences](https://github.com/flutter/packages) - 本地偏好设置
- [url_launcher](https://github.com/flutter/packages) - 外部链接跳转
- [screen_brightness](https://github.com/aaassseee/screen_brightness) - 屏幕亮度控制
- [wakelock_plus](https://github.com/solid-software/wakelock_plus) - 防息屏
- [crypto](https://github.com/dart-lang/core) - 加密工具

以上库均遵循各自的开源许可证。

## 免责声明

**请在使用本应用前仔细阅读以下声明：**

> [!caution]
>
> - 本应用为非官方第三方客户端，仅基于第三方平台提供的接口或公开可访问资源进行内容展示与访问。
> - 本应用不生产、上传、编辑、修改或预先审查具体展示内容，相关内容均来源于第三方返回结果，开发者无法对其进行完全控制。
> - 本应用展示的内容中，可能包含成人内容或其他不适宜未成年人浏览的信息；如您未满 18 周岁，或您所在地法律法规禁止访问相关内容，请立即停止使用本应用。
> - 用户应自行判断相关内容是否适合浏览，并确保其使用行为符合所在地法律法规。
> - 如第三方内容存在侵权、违法、违规或其他不当情形，相关责任原则上由内容提供方承担；开发者将在收到有效通知后，根据实际情况采取必要处理措施。
>
> ✅**继续使用本应用，即表示您已阅读、理解并同意上述说明；如您不同意，请立即停止使用并卸载本应用。**
