<h1 align="center">
<img src="https://files.seeusercontent.com/2026/04/09/hOy5/logo.png"/>
</h1>
<p align="center">
  <img src="https://skills.syvixor.com/api/icons?perline=15&i=flutter,dart,materialdesign"/>
</p>

## 简介

一个热辣漫画的第三方客户端 | A third-party client based on hotmanga

<table>
  <tr>
    <td><img src="https://files.seeusercontent.com/2026/04/09/Nv9r/image-20260409170720476.png"/></td>
    <td><img src="https://files.seeusercontent.com/2026/04/09/ex3Q/image-20260409170916801.png"/></td>
  </tr>
  <tr>
    <td><img src="https://files.seeusercontent.com/2026/04/09/w4qZ/20260409171036966.png"/></td>
    <td><img src="https://files.seeusercontent.com/2026/04/09/tO0b/20260409171139823.png"/></td>
  </tr>  
  <tr>
    <td><img src="https://files.seeusercontent.com/2026/04/09/lmT9/20260409171234851.png"/></td>
    <td><img src="https://files.seeusercontent.com/2026/04/09/c6hF/20260409171942789.png"/></td>
  </tr>
  <tr>
    <td><img src="https://files.seeusercontent.com/2026/04/09/Yr9g/20260409172234773.png"/></td>
    <td><img src="https://files.seeusercontent.com/2026/04/09/mJs4/20260409172416081.png"/></td>
  </tr>
</table> 

## 开发

### 环境要求

- Dart
- Flutter

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

如果你使用vscode，可以直接F5启动调试，你也可以使用下面命令启动：

默认运行：

```sh
flutter run
```

在指定设备上运行：

```sh
flutter run -d win
flutter run -d emulato
```

查看可用设备

```sh
flutter devices
```

如果你本地有Android Studio的虚拟机，可以使用下面命令列出并启动它

```sh
flutter emulators

flutter emulators --launch 上个命令中输出的设备id
```

### 构建安装包

在本地构建apk安装包

```sh
flutter build apk --release --target-platform android-arm64
```

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
