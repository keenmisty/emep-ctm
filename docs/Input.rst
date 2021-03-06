.. _`ch-inputfiles`:

Input files
===========

This chapter provides an overview on the necessary input files to run
the EMEP/MSC-W model. A complete set of input files is provided in the
EMEP/MSC-W Open Source web page to allow model runs for the meteorological
year 2014. :numref:`tab-inputdata` lists the input files.

The input files can be downloaded directly from our
ftp server (ftp://ftp.met.no/projects/emep/OpenSource/201609/),
However, the preferred retrieval method is via the catalog tool
(:numref:`sec-ModelCode`) as follows:

.. code-block:: bash

    # download the meteorology
    catalog.py -R rv4_10 --meteo

    # download other input files
    catalog.py -R rv4_10 --input

The meteorology files will be placed under
``EMEP_MSC-W_model.rv4.10.OpenSource/meteo2014/``,
and the remaining input files will be placed under
``EMEP_MSC-W_model.rv4.10.OpenSource/input/``

This are all input files needed to run the EMEP/MSC-W model,
except the aircraft emissions (``AircraftEmis_FL.nc``),
and forest fire emissions (``FINN_ForestFireEmis_2014.nc``).
See sections :numref:`emisair` and :numref:`emisff`
for details about these emissions data.

IMPORTANT:
    The input data available in the EMEP/MSC-W Open Source Web site should
    be appropriately acknowledged when used for model runs. If nothing else
    is specified according to references further in this chapter, please
    acknowledge EMEP/MSC-W in any use of these data.


.. csv-table:: List of input data files
    :name: tab-inputdata
    :header: **Data**, **Name**, **Format**
    :delim: &

    **Meteorology data**& ``met/``&
    Meteorology& ``meteoYYYYMMDD.nc`` (365+1 files)& netCDF [#YMD]_
    **Other Input files**& ``input/``&
    Global Ozone      & ``GLOBAL_O3.nc``                              & netCDF
    New Global Ozone  & ``Logan_P.nc``                                & netCDF [#NewO3]_
    BVOC emissions    & ``EMEP_EuroBVOC.nc``                          & netCDF
    Landuse           & ``LanduseGLC.nc`` and ``Landuse_PS_5km_LC.nc``& netCDF
    Degree-day factor & ``DegreeDayFactors.nc``                       & netCDF
    N depositions     & ``annualNdep.nc``                             & netCDF
    Road dust         & ``RoadMap.nc`` and ``AVG_SMI_2005_2010.nc``   & netCDF [#Optional]_
    Aircraft emissions& ``AircraftEmis_FL.nc``                        & netCDF [#Optional]_
    Surface Pressure  & ``SurfacePressure.nc``                        & netCDF [#Optional]_
    Forest Fire       & ``FINN_ForestFireEmis_YYYY.nc``               & netCDF [#Optional]_
    Dust files        &  ``Soil_Tegen.nc``                            & netCDF [#Optional]_
                      &  ``SoilTypes_IFS.nc``                         & netCDF [#Optional]_
    Emissions         & ``emislist.POLL`` (7 files, EMEP 50km PS grid)                   & ASCII [#POLL]_
                      & ``Emis_TNO7.nc`` (regional, :math:`0.125\times 0.0625`  lon-lat) & netCDF [#Optional]_
                      & ``Emis_GLOB_05.nc`` (global, :math:`0.5\times 0.5`  lon-lat)     & netCDF [#Optional]_
    Vertical level distribution         & ``Vertical_levels.txt``             & ASCII
    Time factors for monthly emissions  & ``MonthlyFac.POLL`` (7 files)       & ASCII [#POLL]_
    Time factors for daily emissions    & ``DailyFac.POLL`` (7 files)         & ASCII [#POLL]_
    Time factors for hourly emissions   & ``HOURLY-FACS``                     & ASCII
    Emission heights                    & ``EmisHeights.txt``                 & ASCII
    Natural |SO2|                       & ``natso2MM.dat`` (12 files)         & ASCII [#YMD]_
    Volcanoes                           & ``columnsource_emission.csv``       & ASCII
                                        & ``columnsource_location.csv``       & ASCII
    Lightning emissions                 & ``lightningMM.dat`` (12 files)      & ASCII [#YMD]_
    Emissions speciation                & ``emissplit.defaults.POLL``         & ASCII [#POLL]_
                                        & ``emissplit.specials.POLL``         & ASCII [#POLL]_ [#Optional]_
    Emission factors for scenario runs  & ``femis.dat``                       & ASCII
    Photo-dissociation rates            & ``jclearSS.dat`` (4 files)          & ASCII [#SS]_
                                        & ``jcl1kmSS.dat`` (4 files) and ``jcl1.jun`` & ASCII [#SS]_
                                        & ``jcl3kmSS.dat`` (4 files) and ``jcl3.jun`` & ASCII [#SS]_
    Landuse definitions                 & ``Inputs_LandDefs.csv``             & ASCII
    Stomatal conductance                & ``Inputs_DO3SE.csv``                & ASCII
    Sites locations for surface output  & ``sites.dat``                       & ASCII
    Sondes locations for vertical output& ``sondes.dat``                      & ASCII

.. rubric:: Footnotes
.. [#YMD] ``YYYY``: year, ``MM``: month, ``DD``: day.
.. [#NewO3] New |O3| boundary condition data in 30 levels.
     Can be used with ``NewLogan=.true.`` in ``BoundaryConditions_ml.f90``.
.. [#Optional] Optional, in most cases.
.. [#POLL] ``POLL``: pollutant type (|NH3|\ , CO, |NOx|\ , |SOx|\ , NMVOC, |PM25| and |PMco|\ ).
.. [#SS]  ``SS``: seasons.


NetCDF files
------------

Meteorology
~~~~~~~~~~~

The daily meteorological input data (``meteoYYYYMMDD.nc``, where ``YYYY`` is
year, ``MM`` is month and ``DD`` is day) used for the EMEP/MSC-W Model are based
on forecast experiment runs with the Integrated Forecast System (IFS), a
global operational forecasting model from the European Centre for
Medium-Range Weather Forecasts (ECMWF).

The IFS forecasts has been run by MSC-W as independent experiments on
the HPCs at ECMWF with special requests on some output parameters.
The meteorological fields are retrieved on a
:math:`0.1^\circ\times 0.1^\circ` longitude latitude coordinates and
interpolated to :math:`50\times 50 km^2` polar-stereographic grid projection.
Vertically, the fields on 60 eta (\ :math:`\eta`\ ) levels from the IFS model are
interpolated onto the 37 EMEP sigma (\ :math:`\sigma`\ ) levels. The meteorology is prepared
into 37 sigma levels since the model is under test for a finer vertical resolution.

The open source code is released with 20 sigma levels and
to make the model read the meteorology properly, a description of the 20
vertical sigma levels is needed. This is provided in an ASCII file
called ``Vertical_levels.txt`` together with the other input data (:numref:`tab-inputdata`).
The version of the IFS model used for preparing these fields, Cycle 38r2, is
documented in http://www.ecmwf.int/research/ifsdocs/index.html.
Previous years are based on Cycle 36r1 with a resolution of
:math:`0.2^\circ\times 0.2^\circ` on a spherical grid. Meteorological
fields currently used for EMEP/MSC-W Model runs are given in
:numref:`tab-metinput`. Some verification and description of these
meteorological fields are given in Chapter 2 of the EMEP Status Report 1/2016.

Acknowledgement:
    ECMWF, met.no


.. csv-table:: Input meteorological data used in the EMEP/MSC-W Model
    :name: tab-metinput
    :header: **Parameter**, **Unit**, **Description**
    :delim: &

    **3D fields** && for 37 :math:`\sigma`
    :math:`u, v`       & :math:`m/s`       & Horizontal wind velocity components
    :math:`q`          & :math:`kg/kg`     & Specific humidity
    :math:`\theta`     & :math:`K`         & Potential temperature
    :math:`CW`         & :math:`kg/kg`     & Cloud water
    :math:`CL`         & :math:`\%`        & 3D Cloud cover
    :math:`cnvuf`      & :math:`kg/sm^2`   & Convective updraft flux
    :math:`cnvdf`      & :math:`kg/sm^2`   & Convective downdraft flux
    :math:`PR`         & :math:`mm`        & Precipitation
    **2D fields** && for surface
    :math:`PS`         & :math:`hPa`       & Surface pressure
    :math:`T2`         & :math:`K`         & Temperature at :math:`2 m` height
    :math:`Rh2`        & :math:`\%`        & Relative humidity at :math:`2 m` height
    :math:`SH`         & :math:`W/m^2`     & Surface flux of sensible heat
    :math:`LH`         & :math:`W/m^2`     & Surface flux of latent heat
    :math:`\tau`       & :math:`N/m^2`     & Surface stress
    :math:`SST`        & :math:`K`         & Sea surface temperature
    :math:`SWC`        & :math:`m^3/m^3`   & Soil water content
    :math:`lspr`       & :math:`m`         & Large scale precipitation
    :math:`cpr`        & :math:`m`         & Convective precipitation
    :math:`sdepth`     & :math:`m`         & Snow depth
    :math:`ice`        & :math:`\%`        & Fraction of ice
    :math:`SMI1`       &                   & Soil moisture index level 1
    :math:`SMI3`       &                   & Soil moisture index level 3
    :math:`u10, v10`   & :math:`m/s`       & Wind at :math:`10 m` height

.. _`emisnew`:

Gridded emissions
~~~~~~~~~~~~~~~~~

Since 2015 different formats of gridded emissions can be used and
mixed (with some restrictions) under one common framework.
The different formats that are presently supported are:

"Old style" ASCII emissions format:
    Total yearly emissions.

    The gridded emission files contain 16 columns where the first column
    represents the country code
    (http://www.emep.int/grid/country_numbers.txt), the second and the
    third columns are the :math:`i` and :math:`j` indices of the EMEP grid, the
    fourth and fifth columns are the total emissions from low and high
    sources, and the last 11 columns contain emissions from 10
    anthropogenic SNAP sectors.

    The advantage of the ASCII emissions format, is that they are easy to
    modify, and the interpretation of the numbers is straightforward. The
    main disadvantage of the ASCII emissions format, is that they are
    only valid for one specific grid projection. Visualization of these
    emissions, needs also some more efforts.

Countrywise NetCDF emissions:
    Yearly totals.

    Each country and sector has its own NetCDF field.

    The main advantage of NetCDF emissions is that all the information
    about the data (projection, units) is given in the same file. This
    allows the code to reproject the emissions to any grid projection on
    the fly. It is easy to visualize the emissions of one country with
    simple tools, like ncview. The data is simple to interpret and it is
    possible to add new countries to an existing file (with appropriate
    tools).

    The disadvantage of countrywise NetCDF emissions, is that there are
    quite a large number of fields, with most of the data being zero.
    NetCDF will compress the data, but it will still take some time for
    the model to read all the data.

"Fraction type" NetCDF emissions:
    Yearly totals.

    The total emissions are stored in one gridded map, and in addition
    information about which country the emission belongs to.

    The main advantage of "fraction type" NetCDF emissions, is that they
    will keep the grid flexibility, have a more compact form and be
    faster to read in.

    The disadvantage is that the interpretation of the content of the
    fields is more difficult and it is hard, for instance, to add a new
    country to the file. Total emissions and coverage of countries can
    easily be visualized, but not emissions from one single country.

    Description of main fields for "fraction type" NetCDF Emissions
    :numref:`tab-emisdata`

    .. csv-table:: Description of main fields for "fraction type" NetCDF Emissions
        :name: tab-emisdata
        :header: **Variable name**, **Description**
        :delim: &

        ``Ncodes``               & Number of countries sharing the same grid cell
        ``poll_secNN``           & Pollutant from each sector
        ``Codes``                & Country code number
        ``fractions_poll_secNN`` & Fraction of emissions to assign to one country

Monthly "fraction type" NetCDF emissions.
    \

    This is similar to the yearly "fraction type" NetCDF emissions, but
    there are 12 monthly values for each field. This format cannot be
    combined with other formats.

Using and combining gridded emissions
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

These gridded emission files are controlled via the ``config_emep.nml``
file. Each file is assigned as one set of values for ``emis_inputlist``.
:numref:`emis-config` line 1 includes an ASCII emission file, where the
keyword ``POLL`` will be replaced by the model by all the
emitted pollutants (according to the names defined in ``CM_EmisFiles.inc``).
An additional NetCDF emission is included in line 2.

Now all emissions from both ASCII file and NetCDF file will be used. In
practice some countries might be counted twice. Therefore some new data
can be included in the ``emis_inputlist``, to specify which countries to
keep or to avoid. :numref:`emis-config` lines 3--4
will include only 'NO', 'SE' and 'FI' from the first file (ASCII), and
take all countries except 'NO', 'SE' and 'FI' from the second file
(NetCDF).

Sets of countries can in principle be defined; for now only the set
'EUMACC2' is defined.

.. _`emis-config`:

.. code-block:: Fortran
    :caption: Mixed emission configuration example.
    :linenos:

    emis_inputlist(1)%name = '/MyPathToEmissions/emislist.POLL',
    emis_inputlist(2)%name = '/MyPathToEmissions/Emis_GLOB_05.nc',
    emis_inputlist(1)%incl(1:) = 'NO','SE','FI',
    emis_inputlist(2)%excl(1:) = 'NO','SE','FI',
    emis_inputlist(1)%PollName(1:2) = 'voc','sox',


It is also possible to restrict the number of pollutants from each of the files.
If not all pollutants from ``CM_EmisFiles.inc`` are to be read, one can specify a list of pollutants to be included
using "PollName". For instance in the example above , the last line specifies that emissions will include only VOC 
and SOx from the file defined by emis_inputlist(1)%name. 
If PollName is not specified at all, all pollutants are included (therefore all pollutants 
from emis_inputlist(2)%name will be included).
The specified pollutants must already be defined in ``CM_EmisFiles.inc``

Global Ozone
~~~~~~~~~~~~

Initial concentration of ozone are required in order to initialize the
model runs. Boundary conditions along the sides of the model domain and
at the top of the domain are then required as the model is running.

The ``Logan_P.nc`` file contains monthly averaged fields in NetCDF format.
The initial and background concentrations are based on the Logan (1998)
climatology. The Logan climatology is scaled on run time according to the
Mace Head measurements as described in Simpson *et al.* (2003). For a
number of other species, background/initial conditions are set within
the model using functions based on observations (Simpson *et al.*, 2003
and Fagerli *et al.*, 2004).

BVOC emissions
~~~~~~~~~~~~~~

Biogenic emissions of isoprene and monoterpene are calculated in the
model as a function of temperature and solar radiation, using the
landuse datasets. The light and temperature dependencies are similar to
those used in the original open source model, see Chapter 4.2 of the
EMEP Status Report 1/2003 Part I (Simpson *et al.*, 2003).

Biogenic VOC emission potentials (i.e. rates at :math:`30^\circ C` and
full sunlight) are included for four different forest types in the
NetCDF file ``EMEP_EuroBVOC.nc``. These emission potentials have unit
:math:`\mu g/m^2/h`\ , and refer to emissions per area of the
appropriate forest category. In addition, default emission potentials
are given for other land-cover categories in the file
``Inputs_LandDefs.csv``. The underlying emission potentials, land-cover
data bases, and model coding have however changed substantially since
model version v.2011-06. The new approach is documented in Simpson *et
al.*, 2012.

Landuse
~~~~~~~

Landuse data are required for modelling boundary layer processes (i.e.
dry deposition, turbulent diffusion). The EMEP/MSC-W model can accept
landuse data from any data set covering the whole of the domain,
providing reasonable resolution of the vegetation categories. Gridded
data sets providing these landuse categories across the EMEP domain have
been created based on the data from the Stockholm Environment Institute
at York (SEI-Y) and from the Coordinating Center for Effects (CCE). 16
basic landuse classes have been identified for use in the deposition
module in the model, and three additional "fake" landuse classes are
used for providing results for integrated assessment modeling and
effects work.

There are two NetCDF files included, one file
``Landuse_PS_5km_LC.nc`` on 5 km resolution over the EMEP domain,
and a global ``LanduseGLC.nc``. The different landuse types are desribed
in Simpson et al (2012).

Degree-day factor
~~~~~~~~~~~~~~~~~

Domestic combustion which contribute to a large part of SNAP 2, varies
on the daily mean temperature. The variation is based on the heating
degree-day concept. These degree days are pre-calculated for each day
and stored in the file ``DegreeDayFactors.nc``. See Simpson et al. (2012)
section 6.1.2.

|NOx| depositions
~~~~~~~~~~~~~~~~~

Areas with high NO deposition loads have greater soil-NO emissions. To
include this in the model, a NetCDF file where pre-calculated
N-depositions are included. The file made by the results from the
EMEP/MSC-W model runs over a 5-year period.

Road Dust
~~~~~~~~~

Road traffic produces dust. These emissions are handled in the
EMEP/MSC-W model in the ``Emissions_ml.f90`` module. To include road
dust, set ``USE_ROADDUST=.true.`` in ``config_emep.nml``. There are two
files included in input data, ``RoadMap.nc`` and ``AVG_SMI_2005-2010.nc``.
``RoadMap.nc`` include gridded roads and PM emissions over Europe,
``AVG_SMI_2005-2010.nc`` are global.

.. _`emisair`:

Aircraft emissions
~~~~~~~~~~~~~~~~~~

In the EMEP/MSC-W model aircraft emissions are 'OFF' by default. They
can be switched 'ON' by setting ``USE_AIRCRAFT_EMIS=.true.`` in
``config_emep.nml`` and download the data from
http://www.pa.op.dlr.de/quantify. The EMEP model uses data provided by
the EU-Framework Programme 6 Integrated Project QUANTIFY
(http://www.pa.op.dlr.de/quantify). However, before using these data a
protocol has to be signed, which is why the data file can not be
provided directly on the EMEP/MSC-W Open Source website. If you want to
use aircraft emissions go to http://www.pa.op.dlr.de/quantify, click on
'QUANTIFY emission inventories and scenarios', and then click on
'Register'. That page will provide information about the registration
process and the protocol that has to be signed. Once you are registered,
click 'Login' and provide user name and password. On the new page,
search for 'Emissions for EMEP', which links directly to the ``Readme`` file
and the emission data file in NetCDF format. Download the emission data
file and place it in the input folder.

Surface Pressure
~~~~~~~~~~~~~~~~

If ``USE_AIRCRAFT_EMIS=.true``. in ``config_emep.nml``, then in
addition to the Aircraft Emission file, there will be need for a
``SurfacePressure.nc`` file, which is already in the ``/input`` folder. The
NetCDF file consists of surface pressure fields for each of the months
in 2008 called ``surface_pressure``, and one field for the whole year
called ``surface_pressure_year``. All fields are given in Pa.

.. _`emisff`:

Forest Fire
~~~~~~~~~~~

Since model version rv3.9 (November 2011), daily emissions from forest
and vegetation fires are taken from the "Fire INventory from NCAR
version 1.0" (FINNv1, Wiedinmyer et al. 2011). Data are available from
2005, with daily resolution, on a fine :math:`1 km\times1 km` grid.
We store these data on a slightly coarser grid (\ :math:`0.2^\circ\times 0.2^\circ`\ )
globally for access by the EMEP/MSC-W model. To include forest fire
emissions set ``USE_FOREST_FIRES=.true.`` in ``config_emep.nml`` and
download the 2012 GEOS-chem daily data
http://bai.acd.ucar.edu/Data/fire/. The data needs to be stored with
units mole/day in a NetCDF file called ``FINN_ForestFireEmis_2014.nc``
compatible with the ``ForestFire_ml.f90`` module.

Dust files
~~~~~~~~~~

The annual ASCII data for sand and clay fractions as well as the monthly
data for boundary and initial conditions for dust from Sahara are
replaced with a single NetCDF file ``Soil_Tegen.nc`` since 2013. This
covers data for a global domain in :math:`0.5\times 0.5` degree
resolution.

The variables 'sand' and 'clay' gives the fraction (in %) of sand an
clay in the soil for each grid cell over land.

The files are used by the module ``DustProd_ml.f90``, which calculates
windblown dust emissions from soil erosion. Note that the
parametrization is still in the development and testing phase, and is by
default 'turned off'. To include it in the model calculations, set
``USE_DUST=.true.`` in ``config_emep.nml``. The user is recommended to
read carefully documentation and comments in the module ``DustProd_ml.f90``.

There is also a possibility to include boundary and initial conditions
for dust from Sahara. The input file gives monthly dust mixing ratios
(MM - month, e.g. 01, 02, 03,...) for fine and coarse dust from Sahara.
The files are based on calculations from a global CTM at the University
of Oslo for 2000. To include Saharan dust, set ``USE_SAHARA=.true.`` in
``config_emep.nml``.

Another source for dust is an arid surface. This is accounted for by
soilmosture calculations in ``DustProd_ml.f90``. Together with Soil
Water Index from the meteorology files and permanent wilting point (pwp)
from ``SoilTypes_IFS.nc``. This file is global and NetCDF. See Simpson et
al. (2012) section 6.10.

ASCII files
-----------

Natural |SO2|
~~~~~~~~~~~~~~~~~~~~

Natural |SO2| emissions (dimethylsulfide (DMS) from sea) are
provided as monthly gridded files. The values are given at the surface
in :math:`\mu g/m^2` for each grid cell in the domain.

Volcanoes
~~~~~~~~~

Emissions from volcanic passive degassing of |SO2| are included
for the active Italian volcanoes, Etna, Vulcano and Stromboli, and based upon the
officially submitted data. To consider these volcanic emissions, we need
to feed the locations and heights of volcanoes into the model. The input
file ``columnsource_location.csv`` contains the geographical coordinates
(latitudes and longitudes) and the heights (in meters) of the included
volcanoes, while ``columnsource_emission.csv`` contains the emission
parameters.

Since 2010 the EMEP/MSC-W  model has also been used to model the transport of
ash and |SO2| from volcanic eruptions. In addition to data for
passive degassing of |SO2|\ , the above two input files also
contain locations and emission parameters for two recent eruptions of
Icelandic volcanoes (Eyjafjallajökull in 2010 and Grimsvötn in 2011).
In order to include emissions from these eruptions one needs to set
``USE_ASH=.true.`` in ``config_emep.nml``.

Gridded emissions
~~~~~~~~~~~~~~~~~

The official emission input for the EMEP/MSC-W model consists of gridded
annual national emissions based on emission data reported every year to
EMEP/MSC-W (until 2005) and to CEIP (from 2006) by each participating
country. More details about the emission input with references can be
found in Chapter 4 of the EMEP Status Report 1/2003 Part I (Simpson et
al., 2003).

Since 2015 different formats of gridded emissions can be used and mixed
(with some restrictions) in the EMEP model under one common framework.
The new emission system is described in :numref:`emisnew`. Here we focus
only on the "old style" ASCII emission format.

Seven gridded emission input files (``emislist.poll``) are available in
ASCII format for the following compounds: CO, |NH3|\ ,
|NOx|\ , |PM25|\ , |PMco|\ , |SOx| and VOC.

The gridded ASCII emission files contain 16 columns where the first
column represents the country code
(http://www.emep.int/grid/country_numbers.txt), the second and the third
columns are the :math:`i` and :math:`j` indices of the EMEP grid, the fourth and
fifth columns are the total emissions from low and high sources, and the
last 11 columns contain emissions from 10 anthropogenic SNAP sectors
(http://reports.eea.eu.int/technical_report_2001_3/en) and 1
source-sector called "Other sources and sinks", which include natural and
biogenic emission sources. The data are given with the :math:`Mg`\ .

Acknowledgement:
    EMEP

Time factors for emissions
~~~~~~~~~~~~~~~~~~~~~~~~~~

Monthly and daily time factors for emission of the 7 compounds
(CO, |NH3|\ , |NOx|\ , |PM25|\ , |PMco|\ , |SOx| and VOC).
There is one file available per compound in ASCII format.

The first two columns in the files represent the country code
(http://www.emep.int/grid/country_numbers.txt), the second column
represents the sector (http://webdab.emep.int/sectors.html). In the
monthly files, the 12 consecutive columns represent the time factors
corresponding to the months of the year. In the daily files there are 7
consecutive columns representing the time factor for each day of the
week.

The file ``HOURLY-FACS`` includes factors for each of the eleven SNAP
sectors for every hour (the columns) for each day of the week, see
Simpson et al. (2012) section 6.1.2

Emission heights
~~~~~~~~~~~~~~~~

A vertical distribution for the eleven SNAP sectors are given in the
file ``EmisHeights.txt``. The file has seven vertical levels, over the
columns and the SNAP sectors given in the first row. Read more in
Simpson et al. (2012) section 6.1.1.

.. _`sec-femis`:

Emission factor for scenario runs
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Scenario run in the case of the EMEP/MSC-W model means a run
to test the impact of one or more pollutants from a particular country.

Emission factors are applied to specified countries and emission sectors
and can be set by changing the ASCII file ``femis.dat``. This file can
be changed by the users according to their needs.

The file contains several columns (the number is flexible).
The first column represents the country code
(http://www.emep.int/grid/country_numbers.txt), the second represents
the sector (http://reports.eea.eu.int/technical_report_2001_3/en) where
'0' means all sectors, and then in the remaining columns one can specify
which emissions to reduce. Here 1.0 means no reduction of the given
pollutant (|SOx|\ , |NOx|\ , VOC, |NH3|\ , CO, |PM25|\ and |PMco|\ )
from sectors of specified country. The number following the first text ("Name")
in line 1 (number 5 in the downloaded file) gives the number of pollutants
treated in the file.

Chemical speciation of emissions
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Many of the emission files give emissions of a group of compounds, e.g.
|NOx| includes NO+|NO2|\ , and VOC can include many compounds. The
information needed to retrieve emissions of individual compounds from
these the gridded files is given in files labelled
``emissplit.defaults.POLL`` or ``emissplit.specials.POLL``,
where ``POLL`` can be |NOx|\ , VOC, etc.

The defaults file give the emission split for each SNAP sector (one per
row, with second index being the SNAP sector), which is applied to all
countries by default. For VOC this split was derived from the UK
inventory of Passant (2002), as part of the chemical comparison project
of Hayman *et al.* (2011).

The specials files are in general optional, and can be used to specify
speciation for particular countries or SNAP sectors. The 1\ :sup:`st`
column specifies the country code of interest, the second the SNAP
sector.

If forest fires are used, then the file ``emissplit.specials.voc`` is
required (not optional), and the country-code 101 used to specify the
VOC speciation of forest fires in this file.

Lightning emissions
~~~~~~~~~~~~~~~~~~~

Emissions of |NOx| from lightning are included in the model as
monthly averages on T21 (\ :math:`5.65^\circ\times 5.65^\circ`\ )
resolution (Køhler *et al.*, 1995). The lightning emissions are defined
on a :math:`64\times 32` grid with 17 vertical levels, with global
coverage, and are provided as 12 ASCII files ``lightningMM.dat``.

Landuse definitions
~~~~~~~~~~~~~~~~~~~

For the vegetative landuse categories where stomatal modelling is
undertaken, the start and end of the growing season (SGS, EGS, in days)
must be specified. The calculation of SGS and EGS with respect to
latitude is done in the module ``LandDefs_ml.f90``. The parameters
needed to specify the development of the leaf area index (LAI) within
the growing season are given in the ASCII file ``Inputs_LandDefs.csv``.
For more information, see chapter 5 of the EMEP Status Report 1/2003
Part I (Simpson *et al.*, 2003).

The file, designed to be opened with excel or gnumeric, contains a
header briefly explaining the contents of the 14 columns. The first
three columns are representing the landuse name, code (which are
consistent with those in ``Landuse.Input`` file) and type (grouping of the
landuse classes). The fourth column (PFT) gives a plant-functional type
code (for future use), the fifth gives the maximum height of vegetation
(m), the sixth indicates albedo (%) and the seventh indicates
possible source of |NHx| (0 off/1 on, curently not used).
Columns 8 to 11 define the growing season (day number), column 12 and 13
lists the LAI minimum and maximum (\ :math:`m^2/m^2`\ ) and columns 14
and 15 defines the length of the LAI increase and decline periods (no.
of days). Finally, the last four columns give default values of foliar
biomass and biogenic VOC emission potentials. See Simpson et al., (2012)
for details.

Stomatal conductance
~~~~~~~~~~~~~~~~~~~~

Parameters for the stomatal conductance model, deposition of
|O3| and stomatal exchange (DO3SE) must be specified. That are
based upon the ideas in Emberson *et al.*, 2000, and are discussed in
Simpson and Emberson, 2006 and Tuovinen et al. 2004.

The ASCII file ``Inputs_DO3SE.csv`` provides land-phenology data of each
landuse type for stomatal conductance calculations. The data are
summarised in Table 5.1 in Chapter 5 of the EMEP Status Report 1/2003
Part I (Simpson *et al.*, 2003).

The file contains a **header** with the contents of the file, with
different factors needed for each of the landuse classes used in the
EMEP/MSC-W model. The first two columns represent the landuse code
(which are consistent with those in ``Landuse.Input`` file) and name.
The next 22 values are different phenology factors.

Photo-dissociation rates
~~~~~~~~~~~~~~~~~~~~~~~~

The photo-dissociation rates (J-values) are provided as lookup tables.
The method is previously described in Jonson *et al.*, (2001). J-values
are provided as clear sky, light cloud and dense cloud conditions, and
the model interpolates between these according to cloudiness from the
meteorological input data. In the lookup tables data are listed for
every 10 degree latitude at an interval of 1 degree zenith angle at
every model height.

For the two types of cloud conditions there are one ASCII file
averaged for each season (``SS``); 01, 02, 03 and 04. For light cloud the
four seasonal files are called ``jcl1kmSS.dat``, for dense cloud
conditions the four seasonal files are called ``jcl3kmSS.dat``, and then
for clear sky four files called ``jclearSS.dat``. In addittion
there are two files for June called ``jcl1.jun`` and ``jcl3.jun``.

Each file contains 18 columns. The first column is latitude of zenith
angle and then the next 17 are the values for the model levels with the
1/s. For more details about these rates, please read
Chapter 7.2 of the EMEP Status Report 1/2003 Part I (Simpson *et al.*,
2003).

.. _`sec-sitessondes-input`:

Site and Sonde locations for output
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The model provides a possibility for
extra output data of surface concentration for a set of specified
measurement site locations and concentrations for the vertical column
above a set of specified locations. These site and sonde locations are
listed in the ASCII files ``sites.dat`` and ``sondes.dat``
files. These files can be changed by the user, this is described in
:numref:`sec-sitesonde`.
