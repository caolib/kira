<h1 align="center">
	<img src="assets\ic_launcher.png" style="zoom: 33%;" />
</h1>


<p align="center">
  <img src="https://skills.syvixor.com/api/icons?perline=15&i=flutter,dart,materialdesign"/>
</p>

<p align="center">
  <img alt="GitHub License" src="https://img.shields.io/github/license/caolib/kira">
  <img alt="GitHub Issues or Pull Requests" src="https://img.shields.io/github/issues/caolib/kira">
  <img src="https://img.shields.io/github/stars/caolib/kira" alt="Stars"/>
</p>

## 简介

[kira](https://kirakira.dpdns.org/) 是一个拷贝漫画、热辣漫画的第三方客户端

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

环境要求

- Dart
- Flutter
- Java 17

```sh
git clone https://github.com/caolib/kira.git
cd kira
```

如果是安卓设备，第一次使用需要先 build 一次，后续如果 clean 了需要重新 build
```sh
flutter build apk --debug
```

启动
```sh
flutter run -d <设备ID> --dart-define-from-file=.env
```

## 致谢

- [弹弹play](https://www.dandanplay.com/) — 提供弹幕服务
- [繁化姬](https://zhconvert.org/) — 提供简体化服务

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
