# ``DrawingKit``

打包说明:
先用 DrawingKit target 分别在真机 模拟器  maccatalyst 上面 run 一遍
再切到 DrawingKitUtils target 上面(模拟器真机都行) run 一遍, 结束后自然会弹出 xcframework 的路径

1. 使用 modulemap 时 导入  module 要加入 @_implementationOnly 关键字例如 `@_implementationOnly import mapoc`
1. 使用 官方建议的混编方式, 在 DrawingKit.h 里面引入了要使用的 oc 头文件(注意要再 build phases 中修改相关头文件的权限至 public).. 缺点就是会暴露 oc 文件, 外部可以使用

## Overview

<!--@START_MENU_TOKEN@-->Text<!--@END_MENU_TOKEN@-->

## Topics

### <!--@START_MENU_TOKEN@-->Group<!--@END_MENU_TOKEN@-->

- <!--@START_MENU_TOKEN@-->``Symbol``<!--@END_MENU_TOKEN@-->
