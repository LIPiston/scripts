@echo off
setlocal

:: 作者 LIPiston
:: 作用 rime sync 同步脚本，适用于 Windows 平台
:: ================= 配置区 =================
:: 你的服务器名称
set REMOTE_NAME=files.lipiston
:: 服务器上的路径 (如果是根目录就写 /)
set REMOTE_PATH=/rimesync
:: 本地需要同步的文件夹 (请根据实际情况修改)
set LOCAL_PATH=C:\Users\LIPiston\AppData\Roaming\Rime\sync
:: 本地需要同步的文件夹内需要上传的文件夹 (相对于 LOCAL_PATH 的相对路径)
set UPLOAD=home2
:: ==========================================

echo [开始同步] 先从 %REMOTE_NAME% 拉取除 %UPLOAD% 外的文件到 %LOCAL_PATH%，再上传 %UPLOAD% 文件夹...

:: 自动获取你的 rclone.conf 路径并显示，方便你确认
echo 使用配置: 
rclone config file

:: 先从服务器拉取除了 UPLOAD 文件夹外的其他所有文件到 LOCAL_PATH
:: --exclude: 排除指定目录
:: --update: 跳过本地比服务器更新的文件
:: --transfers 4: 同时下载4个文件
rclone sync "%REMOTE_NAME%:%REMOTE_PATH%" "%LOCAL_PATH%" ^
    --progress ^
    --update ^
    --transfers 4 ^
    --buffer-size 32M ^
    --exclude "%UPLOAD%/**"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [失败] 拉取文件出错，请检查网络或配置。
    pause
    exit /b 1
)

:: 再上传本地的 UPLOAD 文件夹到服务器
rclone copy "%LOCAL_PATH%\%UPLOAD%" "%REMOTE_NAME%:%REMOTE_PATH%/%UPLOAD%" ^
    --progress ^
    --update ^
    --transfers 4 ^
    --buffer-size 32M

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [成功] 同步已完成！
) else (
    echo.
    echo [失败] 推送文件出错，请检查网络或配置。
)

pause
