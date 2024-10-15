import requests

def check_robots_txt(url):
    robots_url = f"{url}/robots.txt"
    try:
        response = requests.get(robots_url)
        if response.status_code == 200:
            print(f"robots.txt 文件存在。内容如下：\n{response.text}")
            return response.text
        else:
            print(f"robots.txt 文件不存在或无法访问。状态码：{response.status_code}")
            return None
    except requests.RequestException as e:
        print(f"访问 robots.txt 时发生错误：{e}")
        return None

def check_sitemap_xml(url):
    sitemap_url = f"{url}/sitemap.xml"
    try:
        response = requests.get(sitemap_url)
        if response.status_code == 200:
            print(f"sitemap.xml 文件存在。内容如下（前500字符）：\n{response.text[:500]}...")
            return response.text
        else:
            print(f"sitemap.xml 文件不存在或无法访问。状态码：{response.status_code}")
            return None
    except requests.RequestException as e:
        print(f"访问 sitemap.xml 时发生错误：{e}")
        return None

# 使用示例
base_url = "https://code-agree.github.io"
robots_content = check_robots_txt(base_url)
sitemap_content = check_sitemap_xml(base_url)

# 进一步分析robots.txt（如果存在）
if robots_content:
    if "Disallow: /" in robots_content:
        print("警告：robots.txt 文件可能阻止了所有搜索引擎爬虫！")
    elif "Disallow:" not in robots_content:
        print("robots.txt 文件没有设置任何限制，这是好的。")
    else:
        print("robots.txt 文件有一些限制，请仔细检查以确保它们是有意的。")

# 进一步分析sitemap.xml（如果存在）
if sitemap_content:
    if "<urlset" in sitemap_content:
        print("sitemap.xml 文件格式看起来正确。")
    else:
        print("警告：sitemap.xml 文件可能格式不正确，请检查其内容。")