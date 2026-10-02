# Android · подготовка и публикация 0.1.1

Версия приложения — `0.1.1+3`: на устройстве отображается `0.1.1`, номер Flutter-сборки — `3` (arm64 split APK использует ABI-смещение). Ветка — `app/mobile`, тег — `v0.1.1`. Репозиторий GitHub — `TheSlopHead/Kolibreum` (локальная папка называется `Mut`). Подготовка выполняется локально; сборочный скрипт ничего не отправляет в GitHub. Описание предыдущей версии сохранено в [0.1.0.md](releases/0.1.0.md).

## Подпись и ключ

`android/app/build.gradle.kts` требует отдельную release-подпись; без неё сборка release завершается ошибкой. Debug-сборки продолжают использовать debug-ключ. Постоянный applicationId — `dev.mut.mut_mobile`.

Пример локального пути ключа — `.tooling/signing/mut-release.jks`, настройки и пароли — в `android/key.properties`; наличие этих файлов нужно проверить на компьютере сборки. Оба файла игнорируются Git. Для 0.1.1 требуется **тот же ключ, которым подписана 0.1.0**. **Сохраните резервную копию обоих файлов в надёжном месте до публикации APK.** Не прикладывайте их к GitHub Release, не добавляйте в Git и не заменяйте ключ при следующей версии. Потеря ключа лишает возможности обновлять установленный APK с той же подписью.

Для сборки на другом компьютере перенесите ключ и создайте приватный `android/key.properties`:

```properties
storeFile=/absolute/path/to/mut-release.jks
storePassword=<пароль хранилища>
keyAlias=mut-release
keyPassword=<пароль ключа>
```

При переходе с APK, подписанного прежним debug-ключом, Android не разрешит обычное обновление. Сначала создайте и сохраните зашифрованный backup через mut, проверьте доступ к нему, затем удалите прежнее приложение, установите release APK и восстановите backup. Удаление приложения стирает его локальную библиотеку.

## Повторная сборка

Из корня репозитория, с чистым закоммиченным состоянием `mobile/`:

```sh
./mobile/tool/prepare-release.sh
```

При наличии полного кэша зависимостей можно использовать `MUT_RELEASE_OFFLINE=1 ./mobile/tool/prepare-release.sh`: lockfile по-прежнему проверяется, но `pub get` работает без сети. Если пакет отсутствует в кэше, потребуется обычная команда с доступом к pub.dev.

Скрипт использует Flutter/JDK/Android SDK из игнорируемой `.tooling/`, когда они установлены, либо заданное локальное окружение. Версии: Flutter 3.47.5, Dart 3.13.4, JDK 21, Android SDK 36, build-tools 36.0.0, NDK 28.2.13676358. Зависимости фиксированы `pubspec.lock`; SDK, пароли и Gradle-кэш не входят в Git.

Скрипт выполняет `pub get --enforce-lockfile`, analyze, tests, release build для arm64, проверяет подпись и версию APK. Результат:

```text
mobile/build/releases/v0.1.1/
  mut-0.1.1-android-arm64.apk
  SHA256SUMS
  RELEASE_NOTES.md
  BUILD_INFO.txt
  APK_INFO.txt
  SIGNATURE.txt
```

`BUILD_INFO.txt` записывает исходный коммит и версию SDK. `SIGNATURE.txt` содержит публичные сведения сертификата, без приватного ключа. Для проверки скачанного APK выполните `sha256sum -c SHA256SUMS` в той же папке.

APK поддерживает Android 8.0+ (API 26) и arm64-v8a. Для других архитектур нужна отдельная сборка. AAB предназначен для магазина и напрямую на телефон не устанавливается.

## Перед публикацией

1. Сохраните резервную копию ключа и настроек подписи.
2. Установите APK на реальное arm64-устройство, проверьте импорт EPUB/FB2/PDF, удаление книг, оба режима, текущую страницу, закладки, повторное открытие и блокировку при уходе в фон. Проверьте backup/restore и обновление с той же release-подписью. Unit/widget-тесты и Linux PDFium не заменяют профилирование Android и независимый security review.
   Для версии с форматом v2 проверьте обновление на тестовом мобильном архиве v1: пароль/recovery, миграцию при первом открытии, наличие `vault.v1`, сохранность оригиналов/обложек, метаданных и позиций, v2 backup и восстановление старого v1 backup. Миграция временно требует места для второй зашифрованной копии и сохраняет старую; производительность на устройстве проверяется отдельно. Контракт — [VAULT_FORMAT.md](VAULT_FORMAT.md).
3. Проверьте, что локальный тег `v0.1.1` указывает на коммит из `BUILD_INFO.txt`. Не включайте посторонние изменения между проверенной сборкой и тегом. Если тега ещё нет, после успешной сборки создайте его: `git tag -a v0.1.1 -m 'mut Android 0.1.1'`.

## Отправка и GitHub Release — выполняет владелец

Если локальная ветка и тег подготовлены, из корня репозитория:

```sh
git switch app/mobile
git push origin app/mobile
git push origin v0.1.1
```

Откройте [создание релиза Kolibreum](https://github.com/TheSlopHead/Kolibreum/releases/new). Выберите **тег `v0.1.1`**, заголовок `mut Android 0.1.1`, вставьте [описание 0.1.1](releases/0.1.1.md) и прикрепите APK и `SHA256SUMS` из папки сборки. Отметьте **Set as a pre-release**: это тестовая версия. **Save draft** сохраняет черновик; **Publish release** публикует его.

GitHub Release привязан к тегу конкретного коммита и содержит описание и файлы (assets). GitHub автоматически добавляет архивы исходников ZIP/TAR, но не собирает APK без отдельного workflow. Сейчас `.github/workflows/` отсутствует. Создание release не включает автоматическое обновление приложения и не публикует его в Google Play.

Официальные источники: [About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases), [Managing releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository), [Flutter Android deployment](https://docs.flutter.dev/deployment/android).
