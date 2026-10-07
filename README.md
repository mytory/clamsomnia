# Clamsomnia

MacBook 덮개를 닫고 이동하는 동안에도 작업을 계속할 수 있도록 시스템 잠자기를 잠시 비활성화하는 macOS 메뉴 막대 앱입니다. `pmset -a disablesleep 1` 동작을 메뉴 막대에서 켜고 끕니다.

## 요구 사항

- macOS 14 이상
- Xcode와 Command Line Tools (`xcodebuild -version`으로 확인)
- 설치 시 관리자 권한

현재 개발과 실기기 검증은 macOS 26에서 진행합니다. macOS 14와 15는 빌드 대상이지만 별도 실기기 검증이 필요합니다.

## 소스에서 빌드하고 설치하기

```sh
./Scripts/install.sh
open /Applications/Clamsomnia.app
```

설치 스크립트가 앱과 관리자 도우미를 컴파일하고 로컬에서 서명한 뒤 `/Applications/Clamsomnia.app`, `/Library/PrivilegedHelperTools/com.mytory.Clamsomnia.helper`, `/Library/LaunchDaemons/com.mytory.Clamsomnia.helper.plist`에 설치합니다. 관리자 암호는 설치 중 한 번 요청됩니다. 앱만 빌드하려면 `./Scripts/build.sh`를 실행합니다. 산출물은 `build/`에 있습니다.

새 버전을 설치할 때는 앱을 먼저 종료하고 `./Scripts/install.sh`를 다시 실행하세요.

## 사용하기

첫 실행에서 방지 시간을 분 단위로 설정합니다. 기본 입력값은 300분이며 무제한도 선택할 수 있습니다. 이후 선택은 저장되고 설정에서 바꿀 수 있습니다.

메뉴 막대의 고양이를 좌클릭하면 잠자기 방지가 켜지거나 꺼집니다. 우클릭 메뉴에는 현재 상태, 설정된 방지 시간, 남은 시간, 복구 예정 시각, 설정과 종료 명령이 표시됩니다. 수동으로 Mac을 재우려면 이 메뉴의 **방지 해제 후 잠자기**를 선택하세요.

설정에서 로그인 시 앱 자동 실행과 앱 실행 직후 잠자기 방지 활성화를 각각 선택할 수 있습니다. 두 옵션이 모두 켜져 있으면 로그인 후 새 방지 세션과 타이머가 시작됩니다.

앱이 직접 켠 잠자기 방지는 설정된 시간이 지나거나 앱이 종료되면 해제됩니다. 앱 시작 전에 다른 도구가 이미 켠 잠자기 방지는 앱 종료만으로 해제하지 않습니다. 메뉴 막대 아이콘을 좌클릭하면 그 상태를 직접 끌 수 있습니다.

## 상태 확인과 제거

시스템 설정은 다음 명령으로 읽을 수 있습니다.

```sh
pmset -g | grep SleepDisabled
sudo launchctl print system/com.mytory.Clamsomnia.helper
```

제거할 때는 앱을 종료하고 다음을 실행합니다. 스크립트는 자동 실행 등록을 해제하고, 도우미에 잠자기 설정 복구를 요청한 뒤 설치 파일을 제거합니다.

```sh
./Scripts/uninstall.sh
```

도우미 설치가 손상되어 잠자기 방지가 남은 경우의 수동 복구 명령은 `sudo pmset -a disablesleep 0`입니다. 실행 전 `pmset -g`로 기존 설정을 확인하세요. 이 명령은 다른 도구가 켠 잠자기 방지도 해제합니다.

## 기술 메모

잠자기 제어에는 관리자 권한이 필요한 시스템 설정을 사용합니다. 메뉴 막대 앱은 관리자 권한으로 실행되지 않고, 별도의 `launchd` 도우미가 설정 변경과 타이머 복구를 담당합니다. 방지 시간이 무제한이어도 앱이 종료되면 앱 소유 세션은 복구됩니다.

배터리 부족이나 과열 상황에서는 macOS가 강제로 잠들 수 있습니다. 가방에 넣고 이동할 때는 발열과 배터리 상태를 확인하세요.
