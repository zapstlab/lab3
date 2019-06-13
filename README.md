# ĆWICZENIE: Orkiestracja usług sieciowych z Cloudify w roli NFVO/VNFM i OpenStack w roli VIM

### UWAGA: Terminy NFVO/VNFM i VIM stosujemy tu w rozumieniu architektury ETSI NFV.
# 
## Wprowadzenie

Ćwiczenie pozwala zapoznać się z pełnym procesem tworzenia bluprintów orkiestracyjnych TOSCA na potrzeby orkiestracji usługowej w środowisku zwirtualizowanym. Na poziomie bardziej szczegółowym pozwala porównać specyfikację orkiestracyjną TOSCA w odmianie Cloudify z notacją HOT/HEAT OpenStack, traktując je obie jako przykłady notacji służących do automatyzacji procesu zarządzania cyklem życiowym, odpowiednio, usług sieciowych i usług IaaS.

WYJAŚNIENIE: Architektura naszej platformy jest zbliżona do NFV MANO, ale nie jest jej kanoniczną reprezentacją. W szczególności orkiestrator Cloudify pełni w niej rolę połączonej pary bloków NFVO+VNFM, zaś OpenStack - rolę VIM. Notacja TOSCA w Cloudify nie oddaje specyfiki profilu TOSCA dla NFV (http://docs.oasis-open.org/tosca/tosca-nfv/v1.0/tosca-nfv-v1.0.html), nie używa się też formatu csar do archiwizowania opisów usług i funkcji wirtualnych oraz skryptów konfiguracyjnych; odstępstwa te nie mają jednak wpływu na istotę orkiestracji usług według modelu TOSCA.

Pierwsze dwa ćwiczenia nie wymagały współpracy Cloudify z OpenStack, ponieważ nie tworzyliśmy instancji działających usług (utworzenie maszyny managera Cloudify skryptem Openstack/Heat nie wchodzi w zakres takiej współpracy). W niniejszym ćwiczeniu, do wdrożenia prostej usługi chmurowej z poziomu orkiestratora Cloudify pełniącego łącznie funkcje pary NFVO/VNFM (NFV Orchestrator, VNF Manager), wykorzystamy OpenStack w roli VIM (Virtual Infrastructure Manager).

W ramach ćwiczenia skonfigurujemy Cloudify do współpracy z OpenStack, a następnie przygotujemy i uruchomimy: (1) blueprint TOSCA, który zainstaluje serwer Apache Tomcat na maszynie wirtualnej, oraz (2) blueprint TOSCA, który przetestuje jego działanie z poziomu drugiej maszyny wirtualnej z prostym klientem HTTP. W szczególności, w ramach ćwiczenia zilustrujemy, w jaki sposób Cloudify wykorzystuje OpenStack w roli VIM na potrzeby:

- tworzenia grup zabezpieczeń (mechanizm poziomu OpenStack)
- tworzenia sieci
- tworzenia routerów
- tworzenia maszyn wirtualnych
- uruchamiania skryptów konfiguracyjnych na maszynach wirtualnych.

UWAGA: w ramach ćwiczenia należy wykonać szereg zaplanowanych kroków. Jest jednak możliwe poszerzenie zakresu eksperymentów we własnym zakresie, a nietrywialne i udokumentowane w sprawozdaniu skutecznie przeprowadzone próby, zwłaszcza dotyczące elementów/funkcjonalności spoza zestawu wykorzystywanego w niniejszej instrukcji, będą honorowane bonusowymi punktami w wysokości do 20% maksymalnej nominalnej oceny za całe ćwiczenie.

## Wybrane odnośniki przydatne w ćwiczeniu

- Cloudify: blueprints https://docs.cloudify.co/4.6/developer/blueprints/
    * DSL definitions https://docs.cloudify.co/4.2.0/blueprints/spec-dsl-definitions/
- Cloudify: funkcje wewnętrzne (intrinsic functions) https://docs.cloudify.co/4.6/developer/blueprints/spec-intrinsic-functions/
- Cloudify: specyfikacja typów OpenStack Plugin https://docs.cloudify.co/4.5.0/working_with/official_plugins/openstack/#types
- OpenStack: CLI https://docs.openstack.org/python-openstackclient/ocata/command-list.html

# Przebieg ćwiczenia

## KROK 1: Konfiguracja OpenStack w Cloudify

Przed przystąpieniem do realizacji głównej części ćwiczenia należy skonfigurować dostęp Cloudify do OpenStack podając parametry dostępu do OpenStack pozyskane w pierwszym ćwiczeniu. W tym celu, z użyciem polecenia cfy, należy ustawić tzw. secret values w Cloudify, które będą przechowywać parametry uwierzytelnienia Cloudify w OpenStack:

#### ogólna forma:
```
cfy secrets list
cfy secrets create os_username -s <username>
cfy secrets create os_password -s <password>
cfy secrets create os_tenant_name -s <project name>
cfy secrets create os_keystone_url -s <url-keystone> # <adres-dashbordu-maszyny-OpenStack>:5000/v3
cfy secrets create os_region -s <region name>

cfy secrets list
cfy secrets get os_keystone_url
```
#### przykład:
```
cfy secrets create os_username -s mojlogin_os
cfy secrets create os_password -s mojehaslo_os
cfy secrets create os_tenant_name -s cloudify-test
cfy secrets create os_keystone_url -s http://194.29.169.25:5000/v3
cfy secrets create os_region -s RegionOne
```

Parametry do powyższych sekretów należy odczytać z pliku openrc.sh utworzonego w ćwiczeniu 1, natomiast nazwę regionu należy odczytać z użyciem CLI openstack skonfigurowanego w pierwszym ćwiczeniu (WSKAZÓWKA: w dokumentacji CLI OpenStack znajdź sposób odczytania listy regionów; otwarcie terminala z linią poleceń openstack opisano w ćwiczeniu 1).

UWAGA: sekrety w Cloudify to wygodny mechanizm zapamiętywania parametrów, do których następnie można się odwoływać w różnych konstrukcjach Cloudify, np. w linii poleceń cfy czy blueprintach (rola podobna do linuksowego polecenia source). Jednocześnie sekrety to jedna z funkcji wewnętrznych Cloudify (tzw. intrinsic functions); więcej o funkcjach wewnętrznych znajdziesz pod adresem podanym w części "Wybrane odnośniki przydatne ćwiczeniu".

## KROK 2: Urchomienie Serwera Apache Tomcat

- Zerknij w zawartość Bluprintu blueprint.yaml i przygotuj plik z wartościami wejściowymi dla blueprintu, właściwymi dla Twojego projektu. Wzorzec tego pliku wejściowego znajdziesz w repozytorium pod nazwą values.yaml. Zauważ, że jako wymagane są tylko te parametry wejściowe, które w Blueprincie nie mają zdefiniowanych wartości domyślnych. Identyfikator odmiany maszyny oraz identyfikator obrazu Ubuntu 14.04 odczytaj za pomocą CLI openstack. Samo wykorzystanie pliku values.yaml ma w naszym ćwiczeniu zilustrować dość elastyczną formę dostarczania parametrów wejściowych do blueprintu na potrzeby tworzonego deploymentu: z (dodatkowych) plików zewnętrznych. Wymagane wartości można znaleźć, zależnie od elementu, posługując się albo linią komend openstak (source openrc.sh ..., lista komend wg linku we wstępie), albo konsolą GUI Openstack.

```
 cfy blueprint upload -b apacheserv ./blueprint.yaml
 cfy deployments create -b apacheserv apacheserv-dep --inputs values.yaml
 
```
Wejdź to dashboard Cloudify oraz przejrzyj zawartość utworzonego deploymentu (wejdź w link Deploymnts w liście po lewej stronie). Zauważ sekcje z wartościami wejściowymi (Outputs) oraz wartościami wyjściowymi (od góry, mamy sekcje: Depluyment Topology,, Deployment Nodes, Deployment Outputs / Deployment Outputs/Capabilities, ...). Prześledź zależności pomiędzy tworzonymi obiektami w blueprincie oraz porównaj jego strukturę ze strukturą wzorca HEAT dla OpenStack wykorzystanego w ćwiczeniu 1 do instalacji Cloudify Managera; skomentuj główne zauważone analogie między nimi.

- Uruchom workflow instalacyjny dla uprzednio utworzonego deploymentu:

```
cfy executions start -d apacheserv-dep install
```

Będąc w oknie dashboard pokazującym szczegóły utworzonego deploymentu naciśnij wiersz z poleceniem "Install" - uruchomi to podgląd i zarazem wizualizację procesu instalacji maszyny w OpenStack razem z zależnościami.

- Aby uzyskać bezpośredni dostęp do utworzonej maszyny wirtualnej musisz wykorzystać klucz prywatny utworzony lokalnie przez Cloudify na maszynie cloudify-manager (Cloudify za pośrednictwem OpenStack wgrywa odpowiedni klucz publiczny na tworzoną maszynę wirtualną).
```
sudo cp /etc/cloudify/.ssh/id_rsa /home/centos/key.pem 
sudo chown centos:centos /home/centos/key.pem 
chmod 400 /home/centos/key.pem 
```
- Dostęp do maszyny można uzyskać wykonując następujące polecenie:
```
ssh -i /home/centos/key.pem ubuntu@{vm_external_ip}
```

- Odczytaj zewnętrzny adres IP serwera HTTP i za pomocą przeglądarki zweryfikuj, że masz do niego dostęp.

KOMENTARZ: W ćwiczeniu dla ułatwienia wykorzystujemy Ubuntu 14.04, ponieważ obraz w tej wersji zawiera domyślnie zainstalowany Python, którego wymaga Cloudify. W nowszych wersjah Ubuntu (16., 18.) trzeba byłoby samemu spreparować obraz maszyny z Pythonem i dopiero taki obraz przekazać do OpenStack.  

## KROK 3: Weryfikacja działania serwera za pomocą zewnętrznego klienta HTTP

- Utwórz nowy blueprint o nazwie np. blueprint-ext.yaml, który będzie rozwinięciem tego używanego w kroku 2. 
- Zmodyfikuj w nowym blueprincie grupę zabezpieczeń tak, aby dostęp do portu 80 możliwy był tylko z sieci prywatnej oraz nie był możliwy z zewnątrz, np. z poziomu przeglądarki internetowej wykorzystanej wyżej w kroku 2.
- Nowy blueprint zmodyfikuj tak, aby razem z serwerem HTTP tworzona była dodatkowa maszyna wirtualna - klient HTTP, której celem będzie weryfikacja dostępu (połączenia) do serwera HTTP. Do samej weryfikacji dostępu wykorzystaj skrypt connection.sh, który powinien być wywoływany w momencie tworzenia zależności / interfejsu między serwerem HTTP a klientem HTTP. 
- Po wykonaniu instalacji odczytaj zewnętrzny adres IP serwera HTTP i za pomocą przeglądarki zweryfikuj, że nie masz teraz do niego dostępu.

# Sprawozdanie z ćwiczenia

Udokumentuj poszczególne kroki ćwiczenia zachowując odpowiednią numerację rozdziałów. W odrębnym punkcie podsumuj całe ćwiczenie.
