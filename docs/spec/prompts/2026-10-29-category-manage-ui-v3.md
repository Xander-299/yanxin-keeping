# 任务书原文（2026-10-29 · 分类管理页交互升级 · 第四轮：弹层尺寸 + 浮动入口）

> 用户原话存档（供 SPEC 引用；本文件只存档，不改写）。

新建分类使用的是Bottom Sheet，占用屏幕高度30%就行。
图标的选择应该在点击图标后，图标的选择也使用Bottom Sheet，占用屏幕高度60%。
添加二级分类的入口维持现状，在分类管理页多加一个添加某一级分类的入口，使用FloatButton组件，放在屏幕高度15%的位置，且不可移动，形状为圆形，图标使用加号，trigger="click"，一级用First的首字母F作为图标，二级用Second的首字母S作为图标，依次类推。
ActionSheet改成Flutter的showModalBottomSheet，弹框中的内容 使用线性布局 Column 来构建
