import 'package:flutter/material.dart';
import 'package:flutter_ui/utils/pix_adapted_screen.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_ui/custom_widget/CustomWidget_2_2.dart';
import 'package:flutter_ui/utils/pix_extensions.dart';
import 'package:flutter_ui/utils/pix_base64_string.dart';
import 'package:flutter_ui/custom_widget/CustomWidget_2_22.dart';

class CustomWidget_2_38 extends StatelessWidget {
 CustomWidget_2_38({super.key});
    late final ImageProvider _image_dnup2_23 = MemoryImage(imageStr_dnup2_23.decodeBase64Image());
  late final ImageProvider _image_cqzu2_39 = MemoryImage(imageStr_cqzu2_39.decodeBase64Image());
  late final ImageProvider _image_tyje2_123 = MemoryImage(imageStr_tyje2_123.decodeBase64Image());
  @override
  Widget build(BuildContext context) {
    return SizedBox(
          height: 626.h,
          child: SingleChildScrollView(
            physics: NeverScrollableScrollPhysics(),
            child: Container(
              constraints: BoxConstraints(minWidth: 390.w, minHeight: 626.h),
              padding: EdgeInsets.only(left: 20.w,right: 20.w, top: 4.h,bottom: 28.h),
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(),
              child: Column(
                key: ValueKey("2:38"),
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 18.h,
                children: [
                  SizedBox(
                    height: 191.h,
                    child: SingleChildScrollView(
                      physics: NeverScrollableScrollPhysics(),
                      child: Container(
                        constraints: BoxConstraints(minWidth: 350.w, minHeight: 191.h),
                        padding: EdgeInsets.only(left: 20.w,right: 20.w, top: 20.h,bottom: 20.h),
                        decoration: BoxDecoration(image: DecorationImage(image: _image_cqzu2_39, fit: BoxFit.fill),borderRadius: BorderRadius.circular(24.h),boxShadow: [BoxShadow(color: Color.fromRGBO(255, 122, 46,0.2),offset: Offset(0.w, 8.w),blurRadius: 20.w,)],),
                        clipBehavior: Clip.hardEdge,
                        child: Column(
                          key: ValueKey("2:39"),
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 18.h,
                          children: [
                            SizedBox(
                              width: 310.w,
                              child: SingleChildScrollView(
                                clipBehavior: Clip.none,
                                physics: NeverScrollableScrollPhysics(),
                                scrollDirection: Axis.horizontal,
                                child: Container(
                                  constraints: BoxConstraints(minWidth: 310.w, minHeight: 84.h),
                                  child: Row(
                                    key: ValueKey("2:40"),
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        height: 79.h,
                                        child: SingleChildScrollView(
                                          clipBehavior: Clip.none,
                                          physics: NeverScrollableScrollPhysics(),
                                          child: Container(
                                            constraints: BoxConstraints(minWidth: 163.w, minHeight: 79.h),
                                            child: Column(
                                              key: ValueKey("2:41"),
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              spacing: 4.h,
                                              children: [
                                                Container(
                                                  width: 52.w,
                                                  height: 16.h,
                                                  child: Text("今日目标",
                                                    key: ValueKey("2:42"),
                                                    textAlign: TextAlign.left,
                                                    style: TextStyle(color: Color.fromRGBO(255, 255, 255,0.85098), fontFamily: "Inter", fontWeight: FontWeight.w500, fontSize: 12.6.sp, letterSpacing: 0.w),),),
                                                SizedBox(
                                                  width: 93.w,
                                                  child: SingleChildScrollView(
                                                    clipBehavior: Clip.none,
                                                    physics: NeverScrollableScrollPhysics(),
                                                    scrollDirection: Axis.horizontal,
                                                    child: Container(
                                                      constraints: BoxConstraints(minWidth: 93.w, minHeight: 40.h),
                                                      child: Row(
                                                        key: ValueKey("2:43"),
                                                        mainAxisAlignment: MainAxisAlignment.start,
                                                        crossAxisAlignment: CrossAxisAlignment.end,
                                                        spacing: 4.w,
                                                        children: [
                                                          Container(
                                                            width: 65.w,
                                                            height: 40.h,
                                                            child: Text("2.4",
                                                              key: ValueKey("2:44"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(255, 255, 255,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 39.6.sp, height: 1, letterSpacing: 0.w),),),
                                                          Container(
                                                            width: 24.w,
                                                            height: 16.h,
                                                            child: Text("km",
                                                              key: ValueKey("2:45"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(255, 255, 255,0.701961), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 15.6.sp, height: 1, letterSpacing: 0.w),),),
                                                        ],),),),),
                                                Container(
                                                  width: 163.w,
                                                  height: 15.h,
                                                  child: Text("目标 3.0 km · 本周已完成 4 次",
                                                    key: ValueKey("2:46"),
                                                    textAlign: TextAlign.left,
                                                    style: TextStyle(color: Color.fromRGBO(255, 255, 255,0.701961), fontFamily: "Inter", fontSize: 11.6.sp, letterSpacing: 0.w),),),
                                              ],),),),),
                                      Container(
                                        width: 84.w,
                                        height: 84.h,
                                        child: Stack(
                                          key: ValueKey("2:47"),
                                          clipBehavior: Clip.none,
                                          children: [
                                            Positioned(
                                              width: 84.w,
                                              height: 84.h,
                                              left: 0.w,
                                              top: 0.h,
                                              child: SvgPicture.asset("assets/images/Frame_2_48.svg",
                                                key: ValueKey("2:48"),),),
                                            Positioned(
                                              width: 84.w,
                                              height: 22.h,
                                              left: 0.w,
                                              top: 35.h,
                                              child: Text("80%",
                                                key: ValueKey("2:51"),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(color: Color.fromRGBO(255, 255, 255,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 17.6.sp, letterSpacing: 0.w),),),
                                          ],),),
                                    ],),),),),
                            SizedBox(
                              width: 310.w,
                              child: SingleChildScrollView(
                                clipBehavior: Clip.none,
                                physics: NeverScrollableScrollPhysics(),
                                scrollDirection: Axis.horizontal,
                                child: Container(
                                  constraints: BoxConstraints(minWidth: 310.w, minHeight: 49.h),
                                  child: Row(
                                    key: ValueKey("2:52"),
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 98.w,
                                        child: SingleChildScrollView(
                                          clipBehavior: Clip.none,
                                          physics: NeverScrollableScrollPhysics(),
                                          scrollDirection: Axis.horizontal,
                                          child: Container(
                                            constraints: BoxConstraints(minWidth: 98.w, minHeight: 49.h),
                                            padding: EdgeInsets.only(left: 10.w,right: 10.w, top: 16.h,bottom: 16.h),
                                            decoration: BoxDecoration(color: Color.fromRGBO(255, 255, 255,1),borderRadius: BorderRadius.circular(24.h),),
                                            child: Row(
                                              key: ValueKey("2:53"),
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              spacing: 6.w,
                                              children: [
                                                Container(
                                                  width: 16.w,
                                                  height: 16.h,
                                                  child: SvgPicture.asset("assets/images/play.svg",
                                                    key: ValueKey("2:54"),),),
                                                Container(
                                                  width: 56.w,
                                                  height: 17.h,
                                                  child: Text("开始跑步",
                                                    key: ValueKey("2:56"),
                                                    textAlign: TextAlign.left,
                                                    style: TextStyle(color: Color.fromRGBO(255, 122, 46,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 13.6.sp, letterSpacing: 0.w),),),
                                              ],),),),),
                                      Container(
                                        width: 93.w,
                                        height: 15.h,
                                        child: Text("还差 0.6 km 达标",
                                          key: ValueKey("2:57"),
                                          textAlign: TextAlign.left,
                                          style: TextStyle(color: Color.fromRGBO(255, 255, 255,0.8), fontFamily: "Inter", fontWeight: FontWeight.w500, fontSize: 11.6.sp, letterSpacing: 0.w),),),
                                    ],),),),),
                          ],),),),),
                  SizedBox(
                    height: 119.h,
                    child: SingleChildScrollView(
                      clipBehavior: Clip.none,
                      physics: NeverScrollableScrollPhysics(),
                      child: Container(
                        constraints: BoxConstraints(minWidth: 350.w, minHeight: 119.h),
                        padding: EdgeInsets.only(left: 16.w,right: 16.w, top: 16.h,bottom: 16.h),
                        decoration: BoxDecoration(color: Color.fromRGBO(255, 255, 255,1),borderRadius: BorderRadius.circular(16.h),boxShadow: [BoxShadow(color: Color.fromRGBO(36, 31, 28,0.058824),offset: Offset(0.w, 4.w),blurRadius: 10.w,)],),
                        child: Column(
                          key: ValueKey("2:58"),
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 14.h,
                          children: [
                            SizedBox(
                              width: 318.w,
                              child: SingleChildScrollView(
                                clipBehavior: Clip.none,
                                physics: NeverScrollableScrollPhysics(),
                                scrollDirection: Axis.horizontal,
                                child: Container(
                                  constraints: BoxConstraints(minWidth: 318.w, minHeight: 30.h),
                                  child: Row(
                                    key: ValueKey("2:59"),
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 60.w,
                                        height: 19.h,
                                        child: Text("今日运动",
                                          key: ValueKey("2:60"),
                                          textAlign: TextAlign.left,
                                          style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 14.6.sp, letterSpacing: 0.w),),),
                                      SizedBox(
                                        width: 88.w,
                                        child: SingleChildScrollView(
                                          clipBehavior: Clip.none,
                                          physics: NeverScrollableScrollPhysics(),
                                          scrollDirection: Axis.horizontal,
                                          child: Container(
                                            constraints: BoxConstraints(minWidth: 88.w, minHeight: 30.h),
                                            padding: EdgeInsets.only(left: 4.w,right: 4.w, top: 8.h,bottom: 8.h),
                                            decoration: BoxDecoration(color: Color.fromRGBO(234, 246, 239,1),borderRadius: BorderRadius.circular(999.h),),
                                            child: Row(
                                              key: ValueKey("2:61"),
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  width: 80.w,
                                                  height: 14.h,
                                                  child: Text("较昨日 +0.6 km",
                                                    key: ValueKey("2:62"),
                                                    textAlign: TextAlign.left,
                                                    style: TextStyle(color: Color.fromRGBO(47, 163, 107,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 10.6.sp, letterSpacing: 0.w),),),
                                              ],),),),),
                                    ],),),),),
                            SizedBox(
                              width: 318.w,
                              child: SingleChildScrollView(
                                clipBehavior: Clip.none,
                                physics: NeverScrollableScrollPhysics(),
                                scrollDirection: Axis.horizontal,
                                child: Container(
                                  constraints: BoxConstraints(minWidth: 318.w, minHeight: 43.h),
                                  child: Row(
                                    key: ValueKey("2:63"),
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        height: 43.h,
                                        child: SingleChildScrollView(
                                          clipBehavior: Clip.none,
                                          physics: NeverScrollableScrollPhysics(),
                                          child: Container(
                                            constraints: BoxConstraints(minWidth: 105.33.w, minHeight: 43.h),
                                            child: Column(
                                              key: ValueKey("2:64"),
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              spacing: 4.h,
                                              children: [
                                                Container(
                                                  width: 39.w,
                                                  height: 24.h,
                                                  child: Text("2.4",
                                                    key: ValueKey("2:65"),
                                                    textAlign: TextAlign.left,
                                                    style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 23.6.sp, height: 1, letterSpacing: 0.w),),),
                                                Container(
                                                  width: 54.w,
                                                  height: 15.h,
                                                  child: Text("距离 (km)",
                                                    key: ValueKey("2:66"),
                                                    textAlign: TextAlign.left,
                                                    style: TextStyle(color: Color.fromRGBO(140, 128, 121,1), fontFamily: "Inter", fontSize: 11.6.sp, letterSpacing: 0.w),),),
                                              ],),),),),
                                      Container(
                                        width: 1.w,
                                        height: 32.h,
                                        decoration: BoxDecoration(color: Color.fromRGBO(240, 232, 224,1),),
                                        child: Stack(
                                          key: ValueKey("2:67"),
                                          clipBehavior: Clip.none,),),
                                      SizedBox(
                                        height: 43.h,
                                        child: SingleChildScrollView(
                                          clipBehavior: Clip.none,
                                          physics: NeverScrollableScrollPhysics(),
                                          child: Container(
                                            constraints: BoxConstraints(minWidth: 105.33.w, minHeight: 43.h),
                                            child: Column(
                                              key: ValueKey("2:68"),
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              spacing: 4.h,
                                              children: [
                                                Container(
                                                  width: 66.w,
                                                  height: 24.h,
                                                  child: Text("18:32",
                                                    key: ValueKey("2:69"),
                                                    textAlign: TextAlign.left,
                                                    style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 23.6.sp, height: 1, letterSpacing: 0.w),),),
                                                Container(
                                                  width: 64.w,
                                                  height: 15.h,
                                                  child: Text("时长 (分:秒)",
                                                    key: ValueKey("2:70"),
                                                    textAlign: TextAlign.left,
                                                    style: TextStyle(color: Color.fromRGBO(140, 128, 121,1), fontFamily: "Inter", fontSize: 11.6.sp, letterSpacing: 0.w),),),
                                              ],),),),),
                                      Container(
                                        width: 1.w,
                                        height: 32.h,
                                        decoration: BoxDecoration(color: Color.fromRGBO(240, 232, 224,1),),
                                        child: Stack(
                                          key: ValueKey("2:71"),
                                          clipBehavior: Clip.none,),),
                                      SizedBox(
                                        height: 43.h,
                                        child: SingleChildScrollView(
                                          clipBehavior: Clip.none,
                                          physics: NeverScrollableScrollPhysics(),
                                          child: Container(
                                            constraints: BoxConstraints(minWidth: 105.33.w, minHeight: 43.h),
                                            child: Column(
                                              key: ValueKey("2:72"),
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              spacing: 4.h,
                                              children: [
                                                Container(
                                                  width: 50.w,
                                                  height: 24.h,
                                                  child: Text("7'43",
                                                    key: ValueKey("2:73"),
                                                    textAlign: TextAlign.left,
                                                    style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 23.6.sp, height: 1, letterSpacing: 0.w),),),
                                                Container(
                                                  width: 58.w,
                                                  height: 15.h,
                                                  child: Text("配速 (/km)",
                                                    key: ValueKey("2:74"),
                                                    textAlign: TextAlign.left,
                                                    style: TextStyle(color: Color.fromRGBO(140, 128, 121,1), fontFamily: "Inter", fontSize: 11.6.sp, letterSpacing: 0.w),),),
                                              ],),),),),
                                    ],),),),),
                          ],),),),),
                  SizedBox(
                    height: 164.h,
                    child: SingleChildScrollView(
                      clipBehavior: Clip.none,
                      physics: NeverScrollableScrollPhysics(),
                      child: Container(
                        constraints: BoxConstraints(minWidth: 350.w, minHeight: 164.h),
                        padding: EdgeInsets.only(left: 16.w,right: 16.w, top: 16.h,bottom: 16.h),
                        decoration: BoxDecoration(color: Color.fromRGBO(255, 255, 255,1),borderRadius: BorderRadius.circular(16.h),boxShadow: [BoxShadow(color: Color.fromRGBO(36, 31, 28,0.058824),offset: Offset(0.w, 4.w),blurRadius: 10.w,)],),
                        child: Column(
                          key: ValueKey("2:75"),
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 14.h,
                          children: [
                            SizedBox(
                              width: 318.w,
                              child: SingleChildScrollView(
                                clipBehavior: Clip.none,
                                physics: NeverScrollableScrollPhysics(),
                                scrollDirection: Axis.horizontal,
                                child: Container(
                                  constraints: BoxConstraints(minWidth: 318.w, minHeight: 19.h),
                                  child: Row(
                                    key: ValueKey("2:76"),
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 60.w,
                                        height: 19.h,
                                        child: Text("本周跑量",
                                          key: ValueKey("2:77"),
                                          textAlign: TextAlign.left,
                                          style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 14.6.sp, letterSpacing: 0.w),),),
                                      Container(
                                        width: 58.w,
                                        height: 19.h,
                                        child: Text("12.4 km",
                                          key: ValueKey("2:78"),
                                          textAlign: TextAlign.left,
                                          style: TextStyle(color: Color.fromRGBO(255, 122, 46,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 14.6.sp, letterSpacing: 0.w),),),
                                    ],),),),),
                            SizedBox(
                              width: 318.w,
                              child: SingleChildScrollView(
                                clipBehavior: Clip.none,
                                physics: NeverScrollableScrollPhysics(),
                                scrollDirection: Axis.horizontal,
                                child: Container(
                                  constraints: BoxConstraints(minWidth: 318.w, minHeight: 44.h),
                                  child: Row(
                                    key: ValueKey("2:79"),
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        width: 24.w,
                                        height: 28.h,
                                        decoration: BoxDecoration(color: Color.fromRGBO(255, 199, 154,1),borderRadius: BorderRadius.circular(6.h),),
                                        child: Stack(
                                          key: ValueKey("2:80"),
                                          clipBehavior: Clip.none,),),
                                      Container(
                                        width: 24.w,
                                        height: 44.h,
                                        decoration: BoxDecoration(color: Color.fromRGBO(255, 199, 154,1),borderRadius: BorderRadius.circular(6.h),),
                                        child: Stack(
                                          key: ValueKey("2:81"),
                                          clipBehavior: Clip.none,),),
                                      Container(
                                        width: 24.w,
                                        height: 17.h,
                                        decoration: BoxDecoration(color: Color.fromRGBO(255, 199, 154,1),borderRadius: BorderRadius.circular(6.h),),
                                        child: Stack(
                                          key: ValueKey("2:82"),
                                          clipBehavior: Clip.none,),),
                                      Container(
                                        width: 24.w,
                                        height: 18.h,
                                        decoration: BoxDecoration(color: Color.fromRGBO(255, 122, 46,1),borderRadius: BorderRadius.circular(6.h),),
                                        child: Stack(
                                          key: ValueKey("2:83"),
                                          clipBehavior: Clip.none,),),
                                      Container(
                                        width: 24.w,
                                        height: 4.h,
                                        decoration: BoxDecoration(color: Color.fromRGBO(242, 237, 232,1),borderRadius: BorderRadius.circular(6.h),),
                                        child: Stack(
                                          key: ValueKey("2:84"),
                                          clipBehavior: Clip.none,),),
                                      Container(
                                        width: 24.w,
                                        height: 4.h,
                                        decoration: BoxDecoration(color: Color.fromRGBO(242, 237, 232,1),borderRadius: BorderRadius.circular(6.h),),
                                        child: Stack(
                                          key: ValueKey("2:85"),
                                          clipBehavior: Clip.none,),),
                                      Container(
                                        width: 24.w,
                                        height: 4.h,
                                        decoration: BoxDecoration(color: Color.fromRGBO(242, 237, 232,1),borderRadius: BorderRadius.circular(6.h),),
                                        child: Stack(
                                          key: ValueKey("2:86"),
                                          clipBehavior: Clip.none,),),
                                    ],),),),),
                            SizedBox(
                              width: 318.w,
                              child: SingleChildScrollView(
                                clipBehavior: Clip.none,
                                physics: NeverScrollableScrollPhysics(),
                                scrollDirection: Axis.horizontal,
                                child: Container(
                                  constraints: BoxConstraints(minWidth: 318.w, minHeight: 12.h),
                                  child: Row(
                                    key: ValueKey("2:87"),
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 24.w,
                                        height: 12.h,
                                        child: Text("一",
                                          key: ValueKey("2:88"),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Color.fromRGBO(181, 170, 162,1), fontFamily: "Inter", fontWeight: FontWeight.w500, fontSize: 9.6.sp, letterSpacing: 0.w),),),
                                      Container(
                                        width: 24.w,
                                        height: 12.h,
                                        child: Text("二",
                                          key: ValueKey("2:89"),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Color.fromRGBO(181, 170, 162,1), fontFamily: "Inter", fontWeight: FontWeight.w500, fontSize: 9.6.sp, letterSpacing: 0.w),),),
                                      Container(
                                        width: 24.w,
                                        height: 12.h,
                                        child: Text("三",
                                          key: ValueKey("2:90"),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Color.fromRGBO(181, 170, 162,1), fontFamily: "Inter", fontWeight: FontWeight.w500, fontSize: 9.6.sp, letterSpacing: 0.w),),),
                                      Container(
                                        width: 24.w,
                                        height: 12.h,
                                        child: Text("四",
                                          key: ValueKey("2:91"),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Color.fromRGBO(255, 122, 46,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 9.6.sp, letterSpacing: 0.w),),),
                                      Container(
                                        width: 24.w,
                                        height: 12.h,
                                        child: Text("五",
                                          key: ValueKey("2:92"),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Color.fromRGBO(181, 170, 162,1), fontFamily: "Inter", fontWeight: FontWeight.w500, fontSize: 9.6.sp, letterSpacing: 0.w),),),
                                      Container(
                                        width: 24.w,
                                        height: 12.h,
                                        child: Text("六",
                                          key: ValueKey("2:93"),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Color.fromRGBO(181, 170, 162,1), fontFamily: "Inter", fontWeight: FontWeight.w500, fontSize: 9.6.sp, letterSpacing: 0.w),),),
                                      Container(
                                        width: 24.w,
                                        height: 12.h,
                                        child: Text("日",
                                          key: ValueKey("2:94"),
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Color.fromRGBO(181, 170, 162,1), fontFamily: "Inter", fontWeight: FontWeight.w500, fontSize: 9.6.sp, letterSpacing: 0.w),),),
                                    ],),),),),
                            SizedBox(
                              width: 318.w,
                              child: SingleChildScrollView(
                                clipBehavior: Clip.none,
                                physics: NeverScrollableScrollPhysics(),
                                scrollDirection: Axis.horizontal,
                                child: Container(
                                  constraints: BoxConstraints(minWidth: 318.w, minHeight: 15.h),
                                  child: Row(
                                    key: ValueKey("2:95"),
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 83.w,
                                        height: 15.h,
                                        child: Text("较上周 +2.1 km",
                                          key: ValueKey("2:96"),
                                          textAlign: TextAlign.left,
                                          style: TextStyle(color: Color.fromRGBO(47, 163, 107,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 11.6.sp, letterSpacing: 0.w),),),
                                      Container(
                                        width: 137.w,
                                        height: 15.h,
                                        child: Text("周目标 20 km · 完成 62%",
                                          key: ValueKey("2:97"),
                                          textAlign: TextAlign.left,
                                          style: TextStyle(color: Color.fromRGBO(140, 128, 121,1), fontFamily: "Inter", fontSize: 11.6.sp, letterSpacing: 0.w),),),
                                    ],),),),),
                          ],),),),),
                  SizedBox(
                    width: 350.w,
                    child: SingleChildScrollView(
                      clipBehavior: Clip.none,
                      physics: NeverScrollableScrollPhysics(),
                      scrollDirection: Axis.horizontal,
                      child: Container(
                        constraints: BoxConstraints(minWidth: 350.w, minHeight: 72.h),
                        padding: EdgeInsets.only(left: 14.w,right: 14.w, top: 16.h,bottom: 16.h),
                        decoration: BoxDecoration(color: Color.fromRGBO(255, 255, 255,1),borderRadius: BorderRadius.circular(16.h),boxShadow: [BoxShadow(color: Color.fromRGBO(36, 31, 28,0.058824),offset: Offset(0.w, 4.w),blurRadius: 10.w,)],),
                        child: Row(
                          key: ValueKey("2:98"),
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          spacing: 12.w,
                          children: [
                            SizedBox(
                              height: 40.h,
                              child: SingleChildScrollView(
                                clipBehavior: Clip.none,
                                physics: NeverScrollableScrollPhysics(),
                                child: Container(
                                  constraints: BoxConstraints(minWidth: 40.w, minHeight: 40.h),
                                  decoration: BoxDecoration(color: Color.fromRGBO(255, 246, 230,1),borderRadius: BorderRadius.circular(12.h),),
                                  child: Column(
                                    key: ValueKey("2:99"),
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 20.w,
                                        height: 20.h,
                                        child: SvgPicture.asset("assets/images/trophy0.svg",
                                          key: ValueKey("2:100"),),),
                                    ],),),),),
                            SizedBox(
                              height: 34.h,
                              child: SingleChildScrollView(
                                clipBehavior: Clip.none,
                                physics: NeverScrollableScrollPhysics(),
                                child: Container(
                                  constraints: BoxConstraints(minWidth: 240.w, minHeight: 34.h),
                                  child: Column(
                                    key: ValueKey("2:107"),
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    spacing: 2.h,
                                    children: [
                                      Container(
                                        width: 105.w,
                                        height: 17.h,
                                        child: Text("校园榜 第 128 名",
                                          key: ValueKey("2:108"),
                                          textAlign: TextAlign.left,
                                          style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 13.6.sp, letterSpacing: 0.w),),),
                                      Container(
                                        width: 182.w,
                                        height: 15.h,
                                        child: Text("超越 82% 的校园跑者 · 上升 16 位",
                                          key: ValueKey("2:109"),
                                          textAlign: TextAlign.left,
                                          style: TextStyle(color: Color.fromRGBO(140, 128, 121,1), fontFamily: "Inter", fontSize: 11.6.sp, letterSpacing: 0.w),),),
                                    ],),),),),
                            Container(
                              width: 18.w,
                              height: 18.h,
                              child: SvgPicture.asset("assets/images/chevronright.svg",
                                key: ValueKey("2:110"),),),
                          ],),),),),
                  SizedBox(
                    height: 118.h,
                    child: SingleChildScrollView(
                      clipBehavior: Clip.none,
                      physics: NeverScrollableScrollPhysics(),
                      child: Container(
                        constraints: BoxConstraints(minWidth: 350.w, minHeight: 118.h),
                        child: Column(
                          key: ValueKey("2:112"),
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 12.h,
                          children: [
                            SizedBox(
                              width: 350.w,
                              child: SingleChildScrollView(
                                clipBehavior: Clip.none,
                                physics: NeverScrollableScrollPhysics(),
                                scrollDirection: Axis.horizontal,
                                child: Container(
                                  constraints: BoxConstraints(minWidth: 350.w, minHeight: 20.h),
                                  child: Row(
                                    key: ValueKey("2:113"),
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 68.w,
                                        height: 20.h,
                                        child: Text("运动目标",
                                          key: ValueKey("2:114"),
                                          textAlign: TextAlign.left,
                                          style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 16.6.sp, letterSpacing: 0.w),),),
                                      Container(
                                        width: 52.w,
                                        height: 16.h,
                                        child: Text("查看全部",
                                          key: ValueKey("2:115"),
                                          textAlign: TextAlign.left,
                                          style: TextStyle(color: Color.fromRGBO(255, 122, 46,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 12.6.sp, letterSpacing: 0.w),),),
                                    ],),),),),
                            SizedBox(
                              height: 86.h,
                              child: SingleChildScrollView(
                                clipBehavior: Clip.none,
                                physics: NeverScrollableScrollPhysics(),
                                child: Container(
                                  constraints: BoxConstraints(minWidth: 350.w, minHeight: 86.h),
                                  padding: EdgeInsets.only(left: 16.w,right: 16.w, top: 16.h,bottom: 16.h),
                                  decoration: BoxDecoration(color: Color.fromRGBO(255, 255, 255,1),borderRadius: BorderRadius.circular(16.h),boxShadow: [BoxShadow(color: Color.fromRGBO(36, 31, 28,0.058824),offset: Offset(0.w, 4.w),blurRadius: 10.w,)],),
                                  child: Column(
                                    key: ValueKey("2:116"),
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    spacing: 12.h,
                                    children: [
                                      SizedBox(
                                        width: 318.w,
                                        child: SingleChildScrollView(
                                          clipBehavior: Clip.none,
                                          physics: NeverScrollableScrollPhysics(),
                                          scrollDirection: Axis.horizontal,
                                          child: Container(
                                            constraints: BoxConstraints(minWidth: 318.w, minHeight: 34.h),
                                            child: Row(
                                              key: ValueKey("2:117"),
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              children: [
                                                SizedBox(
                                                  height: 34.h,
                                                  child: SingleChildScrollView(
                                                    clipBehavior: Clip.none,
                                                    physics: NeverScrollableScrollPhysics(),
                                                    child: Container(
                                                      constraints: BoxConstraints(minWidth: 283.w, minHeight: 34.h),
                                                      child: Column(
                                                        key: ValueKey("2:118"),
                                                        mainAxisAlignment: MainAxisAlignment.start,
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        spacing: 2.h,
                                                        children: [
                                                          Container(
                                                            width: 74.w,
                                                            height: 17.h,
                                                            child: Text("每周 20 km",
                                                              key: ValueKey("2:119"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 13.6.sp, letterSpacing: 0.w),),),
                                                          Container(
                                                            width: 148.w,
                                                            height: 15.h,
                                                            child: Text("本周还差 7.6 km · 还剩 3 天",
                                                              key: ValueKey("2:120"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(140, 128, 121,1), fontFamily: "Inter", fontSize: 11.6.sp, letterSpacing: 0.w),),),
                                                        ],),),),),
                                                Container(
                                                  width: 35.w,
                                                  height: 20.h,
                                                  child: Text("62%",
                                                    key: ValueKey("2:121"),
                                                    textAlign: TextAlign.left,
                                                    style: TextStyle(color: Color.fromRGBO(255, 122, 46,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 15.6.sp, letterSpacing: 0.w),),),
                                              ],),),),),
                                      Container(
                                        width: 318.w,
                                        height: 8.h,
                                        decoration: BoxDecoration(color: Color.fromRGBO(245, 237, 230,1),borderRadius: BorderRadius.circular(999.h),),
                                        clipBehavior: Clip.hardEdge,
                                        child: Stack(
                                          key: ValueKey("2:122"),
                                          children: [
                                            Positioned(
                                              width: 197.w,
                                              height: 8.h,
                                              left: 0.w,
                                              top: 0.h,
                                              child: Container(
                                                decoration: BoxDecoration(image: DecorationImage(image: _image_tyje2_123, fit: BoxFit.fill),borderRadius: BorderRadius.circular(999.h),),
                                                child: Stack(
                                                  key: ValueKey("2:123"),
                                                  clipBehavior: Clip.none,),),),
                                          ],),),
                                    ],),),),),
                          ],),),),),
                  SizedBox(
                    height: 226.h,
                    child: SingleChildScrollView(
                      clipBehavior: Clip.none,
                      physics: NeverScrollableScrollPhysics(),
                      child: Container(
                        constraints: BoxConstraints(minWidth: 350.w, minHeight: 226.h),
                        child: Column(
                          key: ValueKey("2:124"),
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 12.h,
                          children: [
                            SizedBox(
                              width: 350.w,
                              child: SingleChildScrollView(
                                clipBehavior: Clip.none,
                                physics: NeverScrollableScrollPhysics(),
                                scrollDirection: Axis.horizontal,
                                child: Container(
                                  constraints: BoxConstraints(minWidth: 350.w, minHeight: 20.h),
                                  child: Row(
                                    key: ValueKey("2:125"),
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 68.w,
                                        height: 20.h,
                                        child: Text("近期运动",
                                          key: ValueKey("2:126"),
                                          textAlign: TextAlign.left,
                                          style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 16.6.sp, letterSpacing: 0.w),),),
                                      Container(
                                        width: 52.w,
                                        height: 16.h,
                                        child: Text("查看全部",
                                          key: ValueKey("2:127"),
                                          textAlign: TextAlign.left,
                                          style: TextStyle(color: Color.fromRGBO(255, 122, 46,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 12.6.sp, letterSpacing: 0.w),),),
                                    ],),),),),
                            SizedBox(
                              height: 194.h,
                              child: SingleChildScrollView(
                                physics: NeverScrollableScrollPhysics(),
                                child: Container(
                                  constraints: BoxConstraints(minWidth: 350.w, minHeight: 194.h),
                                  decoration: BoxDecoration(color: Color.fromRGBO(255, 255, 255,1),borderRadius: BorderRadius.circular(16.h),boxShadow: [BoxShadow(color: Color.fromRGBO(36, 31, 28,0.058824),offset: Offset(0.w, 4.w),blurRadius: 10.w,)],),
                                  clipBehavior: Clip.hardEdge,
                                  child: Column(
                                    key: ValueKey("2:128"),
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 350.w,
                                        child: SingleChildScrollView(
                                          clipBehavior: Clip.none,
                                          physics: NeverScrollableScrollPhysics(),
                                          scrollDirection: Axis.horizontal,
                                          child: Container(
                                            constraints: BoxConstraints(minWidth: 350.w, minHeight: 64.h),
                                            padding: EdgeInsets.only(left: 16.w,right: 16.w, top: 14.h,bottom: 14.h),
                                            child: Row(
                                              key: ValueKey("2:129"),
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              spacing: 12.w,
                                              children: [
                                                SizedBox(
                                                  height: 36.h,
                                                  child: SingleChildScrollView(
                                                    clipBehavior: Clip.none,
                                                    physics: NeverScrollableScrollPhysics(),
                                                    child: Container(
                                                      constraints: BoxConstraints(minWidth: 36.w, minHeight: 36.h),
                                                      decoration: BoxDecoration(color: Color.fromRGBO(255, 241, 230,1),borderRadius: BorderRadius.circular(12.h),),
                                                      child: Column(
                                                        key: ValueKey("2:130"),
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        crossAxisAlignment: CrossAxisAlignment.center,
                                                        children: [
                                                          Container(
                                                            width: 18.w,
                                                            height: 18.h,
                                                            child: SvgPicture.asset("assets/images/sunrise.svg",
                                                              key: ValueKey("2:131"),),),
                                                        ],),),),),
                                                SizedBox(
                                                  height: 34.h,
                                                  child: SingleChildScrollView(
                                                    clipBehavior: Clip.none,
                                                    physics: NeverScrollableScrollPhysics(),
                                                    child: Container(
                                                      constraints: BoxConstraints(minWidth: 202.w, minHeight: 34.h),
                                                      child: Column(
                                                        key: ValueKey("2:140"),
                                                        mainAxisAlignment: MainAxisAlignment.start,
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        spacing: 2.h,
                                                        children: [
                                                          Container(
                                                            width: 85.w,
                                                            height: 17.h,
                                                            child: Text("晨跑 · 3.2 km",
                                                              key: ValueKey("2:141"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 13.6.sp, letterSpacing: 0.w),),),
                                                          Container(
                                                            width: 118.w,
                                                            height: 15.h,
                                                            child: Text("今天 07:12 · 配速 6'12",
                                                              key: ValueKey("2:142"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(140, 128, 121,1), fontFamily: "Inter", fontSize: 11.6.sp, letterSpacing: 0.w),),),
                                                        ],),),),),
                                                SizedBox(
                                                  height: 34.h,
                                                  child: SingleChildScrollView(
                                                    clipBehavior: Clip.none,
                                                    physics: NeverScrollableScrollPhysics(),
                                                    child: Container(
                                                      constraints: BoxConstraints(minWidth: 56.w, minHeight: 34.h),
                                                      child: Column(
                                                        key: ValueKey("2:143"),
                                                        mainAxisAlignment: MainAxisAlignment.start,
                                                        crossAxisAlignment: CrossAxisAlignment.end,
                                                        spacing: 2.h,
                                                        children: [
                                                          Container(
                                                            width: 37.w,
                                                            height: 16.h,
                                                            child: Text("21:40",
                                                              key: ValueKey("2:144"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 12.6.sp, letterSpacing: 0.w),),),
                                                          Container(
                                                            width: 44.w,
                                                            height: 14.h,
                                                            child: Text("+0.4 km",
                                                              key: ValueKey("2:145"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(47, 163, 107,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 10.6.sp, letterSpacing: 0.w),),),
                                                        ],),),),),
                                              ],),),),),
                                      SizedBox(
                                        width: 350.w,
                                        child: SingleChildScrollView(
                                          clipBehavior: Clip.none,
                                          physics: NeverScrollableScrollPhysics(),
                                          scrollDirection: Axis.horizontal,
                                          child: Container(
                                            constraints: BoxConstraints(minWidth: 350.w, minHeight: 1.h),
                                            padding: EdgeInsets.only(left: 0.w,right: 0.w),
                                            child: Row(
                                              key: ValueKey("2:146"),
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  width: 350.w,
                                                  height: 1.h,
                                                  decoration: BoxDecoration(color: Color.fromRGBO(245, 240, 235,1),),
                                                  child: Stack(
                                                    key: ValueKey("2:147"),
                                                    clipBehavior: Clip.none,),),
                                              ],),),),),
                                      SizedBox(
                                        width: 350.w,
                                        child: SingleChildScrollView(
                                          clipBehavior: Clip.none,
                                          physics: NeverScrollableScrollPhysics(),
                                          scrollDirection: Axis.horizontal,
                                          child: Container(
                                            constraints: BoxConstraints(minWidth: 350.w, minHeight: 64.h),
                                            padding: EdgeInsets.only(left: 16.w,right: 16.w, top: 14.h,bottom: 14.h),
                                            child: Row(
                                              key: ValueKey("2:148"),
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              spacing: 12.w,
                                              children: [
                                                SizedBox(
                                                  height: 36.h,
                                                  child: SingleChildScrollView(
                                                    clipBehavior: Clip.none,
                                                    physics: NeverScrollableScrollPhysics(),
                                                    child: Container(
                                                      constraints: BoxConstraints(minWidth: 36.w, minHeight: 36.h),
                                                      decoration: BoxDecoration(color: Color.fromRGBO(255, 241, 230,1),borderRadius: BorderRadius.circular(12.h),),
                                                      child: Column(
                                                        key: ValueKey("2:149"),
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        crossAxisAlignment: CrossAxisAlignment.center,
                                                        children: [
                                                          Container(
                                                            width: 18.w,
                                                            height: 18.h,
                                                            child: SvgPicture.asset("assets/images/moon.svg",
                                                              key: ValueKey("2:150"),),),
                                                        ],),),),),
                                                SizedBox(
                                                  height: 34.h,
                                                  child: SingleChildScrollView(
                                                    clipBehavior: Clip.none,
                                                    physics: NeverScrollableScrollPhysics(),
                                                    child: Container(
                                                      constraints: BoxConstraints(minWidth: 202.w, minHeight: 34.h),
                                                      child: Column(
                                                        key: ValueKey("2:152"),
                                                        mainAxisAlignment: MainAxisAlignment.start,
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        spacing: 2.h,
                                                        children: [
                                                          Container(
                                                            width: 82.w,
                                                            height: 17.h,
                                                            child: Text("夜跑 · 2.1 km",
                                                              key: ValueKey("2:153"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 13.6.sp, letterSpacing: 0.w),),),
                                                          Container(
                                                            width: 123.w,
                                                            height: 15.h,
                                                            child: Text("昨天 20:35 · 配速 7'05",
                                                              key: ValueKey("2:154"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(140, 128, 121,1), fontFamily: "Inter", fontSize: 11.6.sp, letterSpacing: 0.w),),),
                                                        ],),),),),
                                                SizedBox(
                                                  height: 34.h,
                                                  child: SingleChildScrollView(
                                                    clipBehavior: Clip.none,
                                                    physics: NeverScrollableScrollPhysics(),
                                                    child: Container(
                                                      constraints: BoxConstraints(minWidth: 56.w, minHeight: 34.h),
                                                      child: Column(
                                                        key: ValueKey("2:155"),
                                                        mainAxisAlignment: MainAxisAlignment.start,
                                                        crossAxisAlignment: CrossAxisAlignment.end,
                                                        spacing: 2.h,
                                                        children: [
                                                          Container(
                                                            width: 36.w,
                                                            height: 16.h,
                                                            child: Text("14:52",
                                                              key: ValueKey("2:156"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 12.6.sp, letterSpacing: 0.w),),),
                                                          Container(
                                                            width: 30.w,
                                                            height: 14.h,
                                                            child: Text("-0:38",
                                                              key: ValueKey("2:157"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(47, 163, 107,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 10.6.sp, letterSpacing: 0.w),),),
                                                        ],),),),),
                                              ],),),),),
                                      SizedBox(
                                        width: 350.w,
                                        child: SingleChildScrollView(
                                          clipBehavior: Clip.none,
                                          physics: NeverScrollableScrollPhysics(),
                                          scrollDirection: Axis.horizontal,
                                          child: Container(
                                            constraints: BoxConstraints(minWidth: 350.w, minHeight: 1.h),
                                            padding: EdgeInsets.only(left: 0.w,right: 0.w),
                                            child: Row(
                                              key: ValueKey("2:158"),
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Container(
                                                  width: 350.w,
                                                  height: 1.h,
                                                  decoration: BoxDecoration(color: Color.fromRGBO(245, 240, 235,1),),
                                                  child: Stack(
                                                    key: ValueKey("2:159"),
                                                    clipBehavior: Clip.none,),),
                                              ],),),),),
                                      SizedBox(
                                        width: 350.w,
                                        child: SingleChildScrollView(
                                          clipBehavior: Clip.none,
                                          physics: NeverScrollableScrollPhysics(),
                                          scrollDirection: Axis.horizontal,
                                          child: Container(
                                            constraints: BoxConstraints(minWidth: 350.w, minHeight: 64.h),
                                            padding: EdgeInsets.only(left: 16.w,right: 16.w, top: 14.h,bottom: 14.h),
                                            child: Row(
                                              key: ValueKey("2:160"),
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              spacing: 12.w,
                                              children: [
                                                SizedBox(
                                                  height: 36.h,
                                                  child: SingleChildScrollView(
                                                    clipBehavior: Clip.none,
                                                    physics: NeverScrollableScrollPhysics(),
                                                    child: Container(
                                                      constraints: BoxConstraints(minWidth: 36.w, minHeight: 36.h),
                                                      decoration: BoxDecoration(color: Color.fromRGBO(255, 241, 230,1),borderRadius: BorderRadius.circular(12.h),),
                                                      child: Column(
                                                        key: ValueKey("2:161"),
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        crossAxisAlignment: CrossAxisAlignment.center,
                                                        children: [
                                                          Container(
                                                            width: 18.w,
                                                            height: 18.h,
                                                            child: SvgPicture.asset("assets/images/map.svg",
                                                              key: ValueKey("2:162"),),),
                                                        ],),),),),
                                                SizedBox(
                                                  height: 34.h,
                                                  child: SingleChildScrollView(
                                                    clipBehavior: Clip.none,
                                                    physics: NeverScrollableScrollPhysics(),
                                                    child: Container(
                                                      constraints: BoxConstraints(minWidth: 202.w, minHeight: 34.h),
                                                      child: Column(
                                                        key: ValueKey("2:166"),
                                                        mainAxisAlignment: MainAxisAlignment.start,
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        spacing: 2.h,
                                                        children: [
                                                          Container(
                                                            width: 110.w,
                                                            height: 17.h,
                                                            child: Text("校园环跑 · 5.1 km",
                                                              key: ValueKey("2:167"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 13.6.sp, letterSpacing: 0.w),),),
                                                          Container(
                                                            width: 150.w,
                                                            height: 15.h,
                                                            child: Text("10月28日 16:40 · 配速 6'38",
                                                              key: ValueKey("2:168"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(140, 128, 121,1), fontFamily: "Inter", fontSize: 11.6.sp, letterSpacing: 0.w),),),
                                                        ],),),),),
                                                SizedBox(
                                                  height: 34.h,
                                                  child: SingleChildScrollView(
                                                    clipBehavior: Clip.none,
                                                    physics: NeverScrollableScrollPhysics(),
                                                    child: Container(
                                                      constraints: BoxConstraints(minWidth: 56.w, minHeight: 34.h),
                                                      child: Column(
                                                        key: ValueKey("2:169"),
                                                        mainAxisAlignment: MainAxisAlignment.start,
                                                        crossAxisAlignment: CrossAxisAlignment.end,
                                                        spacing: 2.h,
                                                        children: [
                                                          Container(
                                                            width: 39.w,
                                                            height: 16.h,
                                                            child: Text("33:50",
                                                              key: ValueKey("2:170"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 12.6.sp, letterSpacing: 0.w),),),
                                                          Container(
                                                            width: 44.w,
                                                            height: 14.h,
                                                            child: Text("本周最佳",
                                                              key: ValueKey("2:171"),
                                                              textAlign: TextAlign.left,
                                                              style: TextStyle(color: Color.fromRGBO(181, 170, 162,1), fontFamily: "Inter", fontWeight: FontWeight.w500, fontSize: 10.6.sp, letterSpacing: 0.w),),),
                                                        ],),),),),
                                              ],),),),),
                                    ],),),),),
                          ],),),),),
                ],),),),);
  }
}
