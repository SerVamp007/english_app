# WordTen: как получить APK

1. На github.com нажми **+ → New repository**, имя `wordten`, нажми **Create repository**.
2. На странице репозитория нажми **uploading an existing file**.
3. Распакуй архив и перетащи ВСЁ содержимое папки в окно браузера (папки `lib`, `.github` и файл `pubspec.yaml`). Нажми **Commit changes**.
4. Открой вкладку **Actions**. Сборка запустится сама (около 10 минут). Если Actions спросит разрешение, нажми «I understand my workflows, go ahead and enable them».
5. Когда появится зелёная галочка, открой запись сборки, внизу в разделе **Artifacts** скачай **WordTen-apk**. Внутри архива лежит `app-release.apk`.
6. Отправь `app-release.apk` себе в Telegram, скачай на телефон и установи (Android попросит разрешить установку из этого источника).

Если папка `.github` не загрузилась: Actions → **set up a workflow yourself**, вставь туда содержимое файла `workflow-for-copy.yml` и нажми Commit.
Если сборка упала (красный крестик), открой её, скопируй текст ошибки и пришли мне.
