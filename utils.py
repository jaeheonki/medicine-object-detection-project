# %% 구글 공유 데이터 다운로드
def download_data(extract_path="./data"):
    import gdown, zipfile
    gdown.download(f"https://drive.google.com/uc?id=1YgTmJPuppvarVklbkxAO7SK11fI-Siim", "알약데이터.zip", quiet=False)
    with zipfile.ZipFile("알약데이터.zip", "r") as zip_ref:
        zip_ref.extractall(extract_path)
    print("데이터 다운로드 완료!")