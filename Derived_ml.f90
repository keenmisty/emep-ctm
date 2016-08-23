! <Derived_ml.f90 - A component of the EMEP MSC-W Unified Eulerian
!          Chemical transport Model>
!*****************************************************************************!
!*
!*  Copyright (C) 2007-2012 met.no
!*
!*  Contact information:
!*  Norwegian Meteorological Institute
!*  Box 43 Blindern
!*  0313 OSLO
!*  NORWAY
!*  email: emep.mscw@met.no
!*  http://www.emep.int
!*
!*    This program is free software: you can redistribute it and/or modify
!*    it under the terms of the GNU General Public License as published by
!*    the Free Software Foundation, either version 3 of the License, or
!*    (at your option) any later version.
!*
!*    This program is distributed in the hope that it will be useful,
!*    but WITHOUT ANY WARRANTY; without even the implied warranty of
!*    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!*    GNU General Public License for more details.
!*
!*    You should have received a copy of the GNU General Public License
!*    along with this program.  If not, see <http://www.gnu.org/licenses/>.
!*****************************************************************************!

!==============================================================================
module Derived_ml

  !---------------------------------------------------------------------------
  ! DESCRIPTION
  ! This module performs the calculations associated with "derived" 2D and 3D,
  ! such as accumulated precipitation or sulphate, daily, monthly or yearly
  ! averages, depositions. These fields are all typically output as netCDF
  ! fields.
  !
  ! This routine defines many possible derived  outputs.
  ! The names of the derived fields actualy required should have been specified
  !  in the user-defined My_Derived_ml.
  !
  ! User-defined routines and treatments are often needed here. Here there is
  ! added stuff for VOC, AOTs, accsu. In
  ! general such code should be added in such a way that it isn't activated if
  ! not needed. It then doesn't need to be commented out if not used.
  !---------------------------------------------------------------------------

use My_Derived_ml, only : &
            wanted_deriv2d, wanted_deriv3d  &! names of wanted derived fields
           ,Init_My_Deriv, My_DerivFunc
use My_Derived_ml,  only : &
      COLUMN_MOLEC_CM2, &
      COLUMN_LEVELS   , &
      OutputFields,  &
      nOutputFields,  &
      WDEP_WANTED, &
      D3_OTHER

use Aero_Vds_ml,      only: diam  !aerosol MMD (um)
use AOTx_ml,          only: Calc_GridAOTx
use Biogenics_ml,     only: EmisNat, NEMIS_BioNat, EMIS_BioNat
use CheckStop_ml,     only: CheckStop, StopAll
use Chemfields_ml,    only: xn_adv, xn_shl, cfac,xn_bgn, AOD,  &
                            PM25_water, PM25_water_rh50
use ChemGroups_ml     ! SIA_GROUP, PMCO_GROUP -- use tot indices
use ChemSpecs_adv_ml         ! Use NSPEC_ADV amd any of IXADV_ indices
use ChemSpecs_shl_ml
use ChemSpecs_tot_ml
use ChemChemicals_ml, only: species,species_adv
use Chemfields_ml ,   only: so2nh3_24hr,Grid_snow
use DerivedFields_ml, only: MAXDEF_DERIV2D, MAXDEF_DERIV3D, &
                            def_2d, def_3d, f_2d, f_3d, d_2d, d_3d
use EcoSystem_ml,     only: DepEcoSystem, NDEF_ECOSYSTEMS, &
                            EcoSystemFrac,FULL_ECOGRID
use EmisDef_ml,       only: EMIS_FILE
use Emissions_ml,     only: SumSnapEmis
use GridValues_ml,    only: debug_li, debug_lj, debug_proc, sigma_mid, xm2, &
                         GRIDWIDTH_M, GridArea_m2
use Io_Progs_ml,      only: datewrite
use MetFields_ml,     only: roa,pzpbl,Kz_m2s,th,zen, ustar_nwp, z_bnd,u_ref,&
         ws_10m, rh2m
use MetFields_ml,     only: ps, t2_nwp
use MetFields_ml,     only: SoilWater_deep, SoilWater_uppr, Idirect, Idiffuse
use ModelConstants_ml, only: &
   KMAX_MID     & ! =>  z dimension (layer number)
  ,KMAX_BND     & ! =>  z dimension (level number)
  ,NPROC        & ! No. processors
  ,atwS, atwN, ATWAIR, dt_advec  &
  ,PPBINV       & ! 1.0e9, for conversion of units
  ,PPTINV       & ! 1.0e12, for conversion of units
  ,MFAC         & ! converts roa (kg/m3 to M, molec/cm3)
  ,DEBUG_i, DEBUG_j &
  ,DEBUG_AOT       &
  ,DEBUG => DEBUG_DERIVED,  DEBUG_COLUMN, MasterProc &
  ,SOURCE_RECEPTOR &
  ,USE_EMERGENCY,DEBUG_EMERGENCY &
  ,PT           &
  ,FORECAST     & ! only dayly (and hourly) output on FORECAST mode
  ,NTDAY        & ! Number of 2D O3 to be saved each day (for SOMO)
  ! output types corresponding to instantaneous,year,month,day
  ,IOU_INST, IOU_YEAR, IOU_MON, IOU_DAY, IOU_HOUR_PREVIOUS, IOU_HOUR, IOU_HOUR_MEAN

use MosaicOutputs_ml, only: nMosaic, MosaicOutput
use OwnDataTypes_ml, only: Deriv,TXTLEN_DERIV,TXTLEN_SHORT ! type & length of names
use Par_ml,    only: MAXLIMAX,MAXLJMAX, &   ! => max. x, y dimensions
                     me,                &   ! for print outs
                     gi0,gj0,IRUNBEG,JRUNBEG,&! for i_fdom, j_fdom
                     li0,lj0,limax, ljmax    ! => used x, y area
use PhysicalConstants_ml,  only : PI,KAPPA
!FUTURE use Pollen_ml,      only: AreaPOLL
use SmallUtils_ml,  only: find_index, LenArray, NOT_SET_STRING
use TimeDate_ml,    only: day_of_year,daynumber,current_date
use Units_ml,       only: Units_Scale,Group_Units
implicit none
private

 public  :: Init_Derived         !
 public  :: ResetDerived         ! Resets values to zero
 public  :: DerivedProds         ! Calculates any production terms
 public  :: AddDeriv             ! Adds Deriv type to def_2d, def_3d
 public  :: AddNewDeriv          ! Creates & Adds Deriv type to def_2d, def_3d
 private :: Define_Derived       !
 private :: Setups
 private :: write_debug
 private :: write_debugadv

 public :: Derived              ! Calculations of sums, avgs etc.
 private :: voc_2dcalc          ! Calculates sum of VOC for 2d fields
 private :: voc_3dcalc          ! Calculates sum of VOC for 3d fields
 private :: uggroup_calc        ! Calculates sum of groups, e.g. pm25
                                ! from new group arrays


   INCLUDE 'mpif.h'
   INTEGER STATUS(MPI_STATUS_SIZE),INFO
   logical, private, parameter :: T = .true., F = .false. ! shorthands only


   integer, public, save :: num_deriv2d, num_deriv3d
   integer, private, save :: Nadded2d = 0, Nadded3d=0 ! No. defined derived
   integer, public, save :: iou_min=IOU_INST, iou_max=IOU_HOUR_MEAN

  ! The 2-d and 3-d fields use the above as a time-dimension. We define
  ! LENOUTxD according to how fine resolution we want on output. For 2d
  ! fields we use daily outputs. For the big 3d fields, monthly output
  ! is sufficient.

   integer, public, parameter ::  LENOUT2D = IOU_HOUR_PREVIOUS  ! Allows INST..DAY,H.PREV. for 2d fields
   integer, public, parameter ::  LENOUT3D = IOU_DAY            ! Allows INST..DAY for 3d fields

  !will be used for:
  !e.g. d_2d( num_deriv2d,MAXLIMAX, MAXLJMAX, LENOUT2D)
  ! &   d_3d( num_deriv3d,MAXLIMAX, MAXLJMAX, KMAX_MID, LENOUT3D )


   ! save O3 every hour during one day to find running max
    real, save  , allocatable , public :: &     ! to be used for SOMO35
     D2_O3_DAY( :,:,:)

   ! Fraction of NO3_c below 2.5 um (v. crude so far)

     real, save, private :: fracPM25


  ! Counters to keep track of averaging
  ! Initialise to zero in Init.

    integer, public, allocatable, dimension(:,:), save :: nav_2d
    integer, public, allocatable, dimension(:,:), save :: nav_3d


   !-- some variables for the VOC sum done for ozone models
   !   (have no effect in non-ozone models - leave in code)

   integer, private, save :: nvoc   ! No. VOCs
   integer, private, dimension(NSPEC_ADV), save :: &
             voc_index, &     ! Index of VOC in xn_adv
             voc_carbon       ! Number of C atoms

   logical, private, save :: debug_flag, Is3D
   character(len=100), private :: errmsg

   integer, private :: i,j,k,n, ivoc, index    ! Local loop variables

  integer, private, save :: iadv_O3=-999,     & ! Avoid hard codded IXADV_SPCS
    iadv_EC_C_WOOD=-999,iadv_EC_C_FFUEL=-999,iadv_POM_C_FFUEL=-999,  &
    iadv_SO4=-999,iadv_NO3_F=-999,iadv_NO3_C=-999,iadv_NH4_F=-999,   &
    iadv_EC_F_WOOD_AGE=-999,iadv_EC_F_FFUEL_AGE=-999,                &
    iadv_EC_F_WOOD_NEW=-999,iadv_EC_F_FFUEL_NEW=-999,                &
    iadv_PART_OM_F=-999,iadv_SEASALT_F=-999,iadv_SEASALT_C=-999,     &
    iadv_REMPPM25=-999,iadv_REMPPM_C=-999,iadv_DUST_WB_F=-999,       &
    iadv_DUST_WB_C=-999,iadv_DUST_SAH_F=-999,iadv_DUST_SAH_C=-999,   &
    iadv_DUST_ROAD_F=-999,iadv_DUST_ROAD_C=-999,iadv_FFIRE_BC=-999,  &
    iadv_FFIRE_OM=-999, iadv_FFIRE_REMPPM25=-999

  real, private, save :: ug_NO3_C=-999.0,  &             ! Avoid hard codded molwt
    ug_EC_C_WOOD=-999.0,ug_EC_C_FFUEL=-999.0,ug_POM_C_FFUEL=-999.0
  integer, public, save ::                                          &
    spec_SO4=-999,spec_NO3_F=-999,spec_NO3_C=-999,spec_NH4_F=-999,   &
    spec_EC_F_WOOD_AGE=-999,spec_EC_F_FFUEL_AGE=-999,                &
    spec_EC_F_WOOD_NEW=-999,spec_EC_F_FFUEL_NEW=-999,                &
    spec_EC_C_WOOD=-999,spec_EC_C_FFUEL=-999,spec_POM_C_FFUEL=-999,  &
    spec_PART_OM_F=-999,spec_SEASALT_F=-999,spec_SEASALT_C=-999,     &
    spec_REMPPM25=-999,spec_REMPPM_C=-999,spec_DUST_WB_F=-999,       &
    spec_DUST_WB_C=-999,spec_DUST_SAH_F=-999,spec_DUST_SAH_C=-999,   &
    spec_DUST_ROAD_F=-999,spec_DUST_ROAD_C=-999,spec_FFIRE_BC=-999,  &
    spec_FFIRE_OM=-999,spec_FFIRE_REMPPM25=-999
   contains

  !=========================================================================
  subroutine Init_Derived()
    integer :: alloc_err

    allocate(D2_O3_DAY( MAXLIMAX, MAXLJMAX, NTDAY))
     D2_O3_DAY = 0.0

    if(MasterProc .and. DEBUG ) write(*,*) "INIT My DERIVED STUFF"
    call Init_My_Deriv()  !-> wanted_deriv2d, wanted_deriv3d

    ! get lengths of wanted arrays (excludes notset values)
    num_deriv2d = LenArray(wanted_deriv2d,NOT_SET_STRING)
    num_deriv3d = LenArray(wanted_deriv3d,NOT_SET_STRING)

    call CheckStop(num_deriv2d<1,"num_deriv2d<1 !!")

    if(num_deriv2d > 0) then
      if(DEBUG .and. MasterProc ) write(*,*) "Allocate arrays for 2d:",&
                                              num_deriv2d
      allocate(f_2d(num_deriv2d),stat=alloc_err)
      call CheckStop(alloc_err,"Allocation of f_2d")
      allocate(d_2d(num_deriv2d,MAXLIMAX,MAXLJMAX,LENOUT2D),stat=alloc_err)
      call CheckStop(alloc_err,"Allocation of d_2d")
      call CheckStop(alloc_err,"Allocation of d_3d")
      allocate(nav_2d(num_deriv2d,LENOUT2D),stat=alloc_err)
      call CheckStop(alloc_err,"Allocation of nav_2d")
      nav_2d = 0
    endif
    if(num_deriv3d > 0) then
      if(DEBUG .and. MasterProc ) write(*,*) "Allocate arrays for 3d: ",&
                                              num_deriv3d
      allocate(f_3d(num_deriv3d),stat=alloc_err)
      call CheckStop(alloc_err,"Allocation of f_3d")
      allocate(d_3d(num_deriv3d,MAXLIMAX,MAXLJMAX,KMAX_MID,LENOUT3D),&
              stat=alloc_err)
      allocate(nav_3d(num_deriv3d,LENOUT3D),stat=alloc_err)
      call CheckStop(alloc_err,"Allocation of nav_3d")
      nav_3d = 0
    endif

    ! Avoid hard codded IXADV_SPCS
    iadv_O3         =find_index('O3'         ,species_adv(:)%name )
    iadv_SO4        =find_index('SO4'        ,species_adv(:)%name )
    iadv_NO3_F      =find_index('NO3_F'      ,species_adv(:)%name )
    iadv_NO3_C      =find_index('NO3_C'      ,species_adv(:)%name )
    iadv_NH4_F      =find_index('NH4_F'      ,species_adv(:)%name )
    iadv_EC_F_WOOD_AGE=find_index('EC_F_WOOD_AGE',species_adv(:)%name )
    iadv_EC_F_FFUEL_AGE=find_index('EC_F_FFUEL_AGE',species_adv(:)%name )
    iadv_EC_F_WOOD_NEW=find_index('EC_F_WOOD_NEW',species_adv(:)%name )
    iadv_EC_F_FFUEL_NEW=find_index('EC_F_FFUEL_NEW',species_adv(:)%name )
    iadv_EC_C_WOOD  =find_index('EC_C_WOOD'  ,species_adv(:)%name )
    iadv_EC_C_FFUEL =find_index('EC_C_FFUEL' ,species_adv(:)%name )
    iadv_POM_C_FFUEL=find_index('POM_C_FFUEL',species_adv(:)%name )
    iadv_PART_OM_F  =find_index('PART_OM_F'  ,species_adv(:)%name )
    iadv_SEASALT_F  =find_index('SEASALT_F'  ,species_adv(:)%name )
    iadv_SEASALT_C  =find_index('SEASALT_C'  ,species_adv(:)%name )
    iadv_REMPPM25   =find_index('REMPPM25'   ,species_adv(:)%name )
    iadv_REMPPM_C   =find_index('REMPPM_C'   ,species_adv(:)%name )
    iadv_DUST_WB_F  =find_index('DUST_WB_F'  ,species_adv(:)%name )
    iadv_DUST_WB_C  =find_index('DUST_WB_C'  ,species_adv(:)%name )
    iadv_DUST_SAH_F =find_index('DUST_SAH_F' ,species_adv(:)%name )
    iadv_DUST_SAH_C =find_index('DUST_SAH_C' ,species_adv(:)%name )
    iadv_DUST_ROAD_F=find_index('DUST_ROAD_F',species_adv(:)%name )
    iadv_DUST_ROAD_C=find_index('DUST_ROAD_C',species_adv(:)%name )

    iadv_FFIRE_BC   =find_index('FFIRE_BC'   ,species_adv(:)%name )
    iadv_FFIRE_OM   =find_index('FFIRE_OM'   ,species_adv(:)%name )
    iadv_FFIRE_REMPPM25=find_index('FFIRE_REMPPM25',species_adv(:)%name )

    if(iadv_NO3_C      >0)ug_NO3_C      =Units_Scale('ug', iadv_NO3_C      )
    if(iadv_EC_C_WOOD  >0)ug_EC_C_WOOD  =Units_Scale('ug', iadv_EC_C_WOOD  )
    if(iadv_EC_C_FFUEL >0)ug_EC_C_FFUEL =Units_Scale('ug', iadv_EC_C_FFUEL )
    if(iadv_POM_C_FFUEL>0)ug_POM_C_FFUEL=Units_Scale('ug', iadv_POM_C_FFUEL)

    if(iadv_SO4        >0) spec_SO4   = iadv_SO4 + NSPEC_SHL
    if(iadv_NO3_F      >0) spec_NO3_F = iadv_NO3_F + NSPEC_SHL
    if(iadv_NO3_C      >0) spec_NO3_C = iadv_NO3_C + NSPEC_SHL
    if(iadv_NH4_F      >0) spec_NH4_F = iadv_NH4_F + NSPEC_SHL
    if(iadv_EC_F_WOOD_AGE>0) spec_EC_F_WOOD_AGE = iadv_EC_F_WOOD_AGE + NSPEC_SHL
    if(iadv_EC_F_FFUEL_AGE>0) spec_EC_F_FFUEL_AGE = iadv_EC_F_FFUEL_AGE + NSPEC_SHL
    if(iadv_EC_F_WOOD_NEW>0) spec_EC_F_WOOD_NEW = iadv_EC_F_WOOD_NEW + NSPEC_SHL
    if(iadv_EC_F_FFUEL_NEW>0) spec_EC_F_FFUEL_NEW = iadv_EC_F_FFUEL_NEW + NSPEC_SHL
    if(iadv_PART_OM_F  >0) spec_PART_OM_F  = iadv_PART_OM_F   + NSPEC_SHL
    if(iadv_SEASALT_F  >0) spec_SEASALT_F  = iadv_SEASALT_F   + NSPEC_SHL
    if(iadv_SEASALT_C  >0) spec_SEASALT_C  = iadv_SEASALT_C   + NSPEC_SHL
    if(iadv_REMPPM25   >0) spec_REMPPM25   = iadv_REMPPM25    + NSPEC_SHL
    if(iadv_REMPPM_C   >0) spec_REMPPM_C   = iadv_REMPPM_C    + NSPEC_SHL
    if(iadv_DUST_WB_F  >0) spec_DUST_WB_F  = iadv_DUST_WB_F   + NSPEC_SHL
    if(iadv_DUST_WB_C  >0) spec_DUST_WB_C  = iadv_DUST_WB_C   + NSPEC_SHL
    if(iadv_DUST_SAH_F >0) spec_DUST_SAH_F = iadv_DUST_SAH_F  + NSPEC_SHL
    if(iadv_DUST_SAH_C >0) spec_DUST_SAH_C = iadv_DUST_SAH_C  + NSPEC_SHL
    if(iadv_DUST_ROAD_F>0) spec_DUST_ROAD_F= iadv_DUST_ROAD_F + NSPEC_SHL
    if(iadv_DUST_ROAD_C>0) spec_DUST_ROAD_C= iadv_DUST_ROAD_C + NSPEC_SHL
    if(iadv_FFIRE_BC   >0) spec_FFIRE_BC   = iadv_FFIRE_BC    + NSPEC_SHL
    if(iadv_FFIRE_OM   >0) spec_FFIRE_OM   = iadv_FFIRE_OM    + NSPEC_SHL
    if(iadv_FFIRE_REMPPM25 >0) spec_FFIRE_REMPPM25 = iadv_FFIRE_REMPPM25+ NSPEC_SHL

    call Define_Derived()
    call Setups()  ! just for VOC now

    select case(nint(diam(2)*1e7))
    case(25);fracPM25=0.37
    case(30);fracPM25=0.27
    endselect
    if(DEBUG)print *,  ' CFAC INIT PMFRACTION ', fracPM25, diam(2), nint(1.0e7*diam(2))
    call CheckStop( fracPM25 < 0.01, "NEED TO SET FRACPM25")

  end subroutine Init_Derived

   !=========================================================================
    subroutine AddNewDeriv( name,class,subclass,txt,unit,index,f2d,&
           dt_scale,scale, avg,iotype,Is3D)
           !FEN2011 dt_scale,scale, avg,inst,year,month,day,Is3D)

       character(len=*), intent(in) :: name ! e.g. DDEP_SO2_m2Conif
       character(len=*), intent(in) :: class ! Type of data, e.g. ADV or VOC
       character(len=*), intent(in) :: subclass !
       character(len=*), intent(in) :: txt ! text where needed, e.g. "Conif"
       character(len=*), intent(in) :: unit ! writen in netCDF output
       integer, intent(in)  :: index    ! index in concentation array, or other
       integer, intent(in) :: f2d       ! index in f_2d arrays
       logical, intent(in) :: dt_scale  !  where scaling by dt_advec needed,
       real, intent(in)    :: scale     !  e.g. use 100.0 to get cm/s
       logical, intent(in)  :: avg      ! True => average data (divide by
                           ! nav at end),  else accumulate over run period
       integer, intent(in)  :: iotype   ! sets daily, monthly, etc.

       logical, intent(in), optional :: Is3D
       type(Deriv) :: inderiv

if( trim(name) == "HMIX" .and. MasterProc ) print *, "ADDNEWDERIVE", iotype !NOV2011
       inderiv = Deriv(trim(name),trim(class),trim(subclass),&
                           trim(txt),trim(unit),index,f2d,dt_scale, scale,&
                            avg,iotype)
                            !FEN2011 avg,inst,year,month,day)

       if ( present(Is3D) ) then
          call AddDeriv(inderiv,Is3D)
       else
          call AddDeriv(inderiv)
       end if

    end subroutine AddNewDeriv
   !=========================================================================
    subroutine AddDeriv(inderiv,Is3D)

       type(Deriv), intent(in) :: inderiv
       logical, intent(in), optional :: Is3D
       logical :: Is3D_local

       Is3D_local = .false.
       if ( present(Is3D) ) Is3D_local = Is3D

       if ( Is3D_local ) then
         Nadded3d = Nadded3d + 1
         N = Nadded3d
         if ( DEBUG .and. MasterProc   ) &
                  write(*,*) "Define 3d deriv ", N, trim(inderiv%name)
         call CheckStop(N>MAXDEF_DERIV3D,"Nadded3d too big!")
         def_3d(N) = inderiv

       else
         Nadded2d = Nadded2d + 1
         N = Nadded2d
         if (  DEBUG .and. MasterProc ) &
            write(*,"((a,i4,1x,4a,i4))") "DEBUG AddDeriv 2d ", N, &
               trim(inderiv%name), " Class:", trim(inderiv%class), &
              " Ind:", inderiv%index
         !if (  DEBUG .and. MasterProc )  write(*,*) "DALL", inderiv
         call CheckStop(N>MAXDEF_DERIV2D,"Nadded2d too big!")
         def_2d(N) = inderiv

       end if

    end subroutine AddDeriv
   !=========================================================================
    subroutine Define_Derived()

   ! Set the parameters for the derived parameters, including the codes
   ! used by MET.NO/xfelt and scaling factors. (The scaling factors may
   ! be changed later in Derived_ml.
   ! And, Initialise the fields to zero.

    real    :: unitscale
    logical :: volunit   ! set true for volume units, e.g. ppb
    logical :: outmm, outdd  ! sets time-intervals

    character(len=30) :: dname, txt, txt2, class
    character(len=10) :: unittxt
    character(len=3)  :: subclass
    character(len=TXTLEN_SHORT) ::  outname, outunit, outtyp, outdim
    integer :: outind

   integer :: ind, iadv, itot, idebug, n, n2, iLC, igrp, iout

  ! - And to check if a wanted field has been previously defined.
        integer, dimension(MAXDEF_DERIV2D) :: found_ind2d = 0
        integer, dimension(MAXDEF_DERIV3D) :: found_ind3d = 0


    if(DEBUG .and. MasterProc ) write(6,*) " START DEFINE DERIVED "
    !   same mol.wt assumed for PPM25 and PPMCOARSE


!-- Deposition fields. Define all possible fields and their xfelt codes here:

      !code class  avg? ind scale rho Inst Yr Mn Day   name      unit

  Is3D = .false.


! We process the various combinations of gas-species and ecosystem:
! stuff from My_Derived

!-------------------------------------------------------------------------------
  do n = 1, nMosaic
    if ( DEBUG.and.MasterProc ) write(*,*) "DEBUG into AddDeriv ", n, MosaicOutput(n)
    call AddDeriv( MosaicOutput(n) )
  end do
!-------------------------------------------------------------------------------
! Areas of deposition-related ecosystems. Set externally
  do n = 1, NDEF_ECOSYSTEMS
     if(DEBUG.and.MasterProc) write(*,*) "ECODEF ",n, trim( DepEcoSystem(n)%name )

     call AddDeriv( DepEcoSystem(n) )

  end do
!!-------------------------------------------------------------------------------

      !Deriv(name, class,    subc,  txt,           unit
      !Deriv index, f2d, dt_scale, scale, avg? rho Inst Yr Mn Day atw
      ! for AOT we can use index for the threshold, usually 40
call AddNewDeriv( "AOT40_Grid", "GRIDAOT","subclass","-", "ppb h", &
           40, -99, T, 1.0/3600.0, F,   IOU_DAY    )
!
!-------------------------------------------------------------------------------
!-- Tropospheric columns
!
  do n = 1, size(COLUMN_MOLEC_CM2)
  do n2 = 1, size(COLUMN_LEVELS)

    itot = COLUMN_MOLEC_CM2(n)
    iadv = itot - NSPEC_SHL
      !Deriv(name, class,    subc,  txt,           unit
      !Deriv index, f2d, dt_scale, scale, avg? rho Inst Yr Mn Day atw
     dname = "COLUMN_" //trim(species( itot )%name) //"_"//COLUMN_LEVELS(n2)
     subclass = COLUMN_LEVELS(n2)
     read(unit=subclass(2:3),fmt="(i2)") iLC  ! Faking vertical index with iLC :-(
     call AddNewDeriv( dname, "COLUMN ",subclass,"-", "molec/cm2", &
               iadv, -99,  F,    1.0,     T,   IOU_DAY )
  end do
  end do
!-------------------------------------------------------------------------------
!
       !Deriv(name, class,    subc,  txt,           unit
      !Deriv index, f2d, dt_scale, scale, avg? rho Inst Yr Mn Day atw

! NOT YET: Scale pressure by 0.01 to get hPa
call AddNewDeriv( "PSURF ","PSURF",  "SURF","-",   "hPa", &
               -99,  -99,  F,  1.0,  T,   IOU_DAY )


call AddNewDeriv( "Snow_m","SNOW",  "-","-",   "m", &
               -99,  -99,  F,  1.0,  T,  IOU_DAY )


call AddNewDeriv( "USTAR_NWP","USTAR_NWP",  "-","-",   "m/s", &
               -99,  -99, F, 1.0,  T,  IOU_DAY )
!Added for TFMM scale runs
call AddNewDeriv( "Kz_m2s","Kz_m2s",  "-","-",   "m2/s", &
               -99,  -99, F, 1.0,  T,  IOU_DAY )

!Most met params are now better specified in My_Derived.
!MOVED call AddNewDeriv( "ws_10m","ws_10m",  "-","-",   "m/s", &
!MOVED call AddNewDeriv( "HMIX  ","HMIX",  "-","-",   "m", &
! "HMIX00","HMIX12", ....

call AddNewDeriv( "u_ref","u_ref",  "-","-",   "m/s", &
               -99,  -99, F, 1.0,  T,  IOU_DAY )

!call AddNewDeriv( "SoilWater_deep","SoilWater_deep",  "-","-",   "m", &
!               -99,  -99, F, 1.0,  T,  IOU_DAY )
!call AddNewDeriv( "SoilWater_uppr","SoilWater_uppr",  "-","-",   "m", &
!               -99,  -99, F, 1.0,  T,  IOU_DAY )

       !Deriv(name, class,    subc,  txt,           unit
      !Deriv index, f2d, dt_scale, scale, avg? rho Inst Yr Mn Day atw

call AddNewDeriv( "T2m","T2m",  "-","-",   "deg. C", &
               -99,  -99, F, 1.0,  T,  IOU_DAY )
call AddNewDeriv( "Idirect","Idirect",  "-","-",   "W/m2", &
               -99,  -99, F, 1.0,  T,  IOU_DAY )
call AddNewDeriv( "Idiffuse","Idiffuse",  "-","-",   "W/m2", &
               -99,  -99, F, 1.0,  T,  IOU_DAY )


! OutputFields can contain both 2d and 3d specs. We automatically
! set 2d if 3d wanted

do ind = 1, nOutputFields  !!!!size( OutputFields(:)%txt1 )

   outname = trim( OutputFields(ind)%txt1 )
   outunit= trim( OutputFields(ind)%txt2 )   ! eg ugN, which gives unitstxt ugN/m3
   outdim = trim( OutputFields(ind)%txt3 )   ! 2d or 3d
   outtyp = trim( OutputFields(ind)%txt5 )   ! SPEC or GROUP
   outind = OutputFields(ind)%ind    !  H, D, M - fequency of output
   txt2   = "-" ! not needed?

  if ( outtyp == "MISC" ) then ! Simple species

    iout  = -99 ! find_index( wanted_deriv2d(i), def_2d(:)%name )
    class = trim(OutputFields(ind)%txt4)
    unitscale = 1.0
    if(outunit=="ppb") unitscale = PPBINV
    if(any(class==(/"PM25      ","PM25X     ",&
                    "PM25_rh50 ","PM25X_rh50","PM10_rh50 "/)))then
      iadv = -1 ! Units_Scale(iadv=-1) returns 1.0
                ! uggroup_calc gets the unit conversion factor from Group_Units
      unitscale = Units_Scale(outunit, iadv, unittxt, volunit)
      if(MasterProc) write(*,*)"FRACTION UNITSCALE ", unitscale
    endif

    if(MasterProc ) write(*,"(i3,a,i4,a)")  me, &
        "Deriv:D2MET " // trim(outname), outind, trim(class)

    call AddNewDeriv( outname,class,  "-","-",  outunit, &
                  iout,  -99,  F, unitscale,  T, outind )

  else ! SPEC and GROUPS of specs.

    select case(outtyp)
    case("SPEC")  ! Simple species
      iadv = find_index(outname, species_adv(:)%name )
      call CheckStop(iadv<0,"OutputFields Species not found "//trim(outname))
      txt = "SURF_UG"
      iout = iadv
    case("GROUP") ! groups of species
      iadv = -1     ! Units_Scale(iadv=-1) returns 1.0
                    ! uggroup_calc gets the unit conversion factor from Group_Units
      igrp = find_index(outname, GROUP_ARRAY(:)%name )
!-- Emergency: Volcanic Eruption. Skipp groups if not found
      if(outname(1:3)=="ASH")then
        if(MasterProc.and.USE_EMERGENCY.and.DEBUG_EMERGENCY)&
          write(*,"(A,1X,I0,':',A)")'EMERGENCY: group ',igrp,trim(outname)
        if(igrp<1)cycle
      endif
      call CheckStop(igrp<0,"OutputFields Group not found "//trim(outname))
      txt = "SURF_UG_GROUP"   ! ppb not implementde yet
      iout = igrp
    case default
      call StopAll("Derived:OutputFields Error "//trim(outtyp)//":"//trim(outname))
    endselect

    unitscale = Units_Scale(outunit, iadv, unittxt, volunit)

    class = "SURF_MASS_" // trim(outtyp)
    if(volunit) class = "SURF_PPB_" // trim(outtyp)
    call CheckStop(class=="SURF_PPB_GROUP",&
      "SURF_PPB_GROUPS not implemented yet:"// trim(dname) )

    dname = "SURF_" // trim( outunit ) // "_" // trim( outname )

    if( DEBUG.and.MasterProc ) write(*,"(a,2i4,3(1x,a),2L3,i4,es10.2)") &
    "ADD   ", ind, iout, trim(dname),";", trim(class), outmm, outdd, &
          OutputFields(ind)%ind,unitscale

    call AddNewDeriv( dname, class, "-", "-", trim( unittxt ) , &
          iout  , -99,  F,   unitscale,     T,  OutputFields(ind)%ind )

    if(outdim == "3d") then

      class = "3D_MASS_"//trim(outtyp)
      if(volunit .and. iadv > 0) class = "3D_PPB_"//trim(outtyp)

      dname = "D3_"//trim(outunit)//"_"//trim(outname)

      ! Always print out 3D info. Good to help avoid using 3d unless really needed!
      if( MasterProc ) write(*,"(a,3(1x,a),a,L3,a,L3,i4,es10.2)") " ADDED 3D outputs",  &
        trim(dname)," ; class =", trim(class), ', monthly =',outmm,', daily =',outdd
        !, OutputFields(ind)%ind,unitscale

      call AddNewDeriv(dname, class, "-", "-", trim( unittxt ) , &
          iout  , -99, F,   unitscale,     T,   OutputFields(ind)%ind, &
          Is3D=.true. )
    endif ! 3d

   endif
enddo ! OutputFields

!<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

!<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

do ind = 1, size(WDEP_WANTED(:)%txt1)
  dname = "WDEP_"//trim(WDEP_WANTED(ind)%txt1)
  select case(WDEP_WANTED(ind)%txt2)
  case("PREC")
    call AddNewDeriv("WDEP_PREC","PREC ","-","-", "mm",  &
                      -1, -99,   F,    1.0,   F,    IOU_DAY )
  case("SPEC")
    iadv = find_index(WDEP_WANTED(ind)%txt1, species_adv(:)%name)
    call CheckStop(iadv<1, "WDEP_WANTED Species not found " // trim(dname) )

    unitscale = Units_Scale(WDEP_WANTED(ind)%txt3, iadv, unittxt)
    call AddNewDeriv( dname, "WDEP", "-", "-", unittxt , &
            iadv, -99,   F, unitscale,     F,  IOU_DAY)
  case("GROUP")
    igrp = find_index(dname, chemgroups(:)%name)
    call CheckStop(igrp<1, "WDEP_WANTED Group not found " // trim(dname) )

    ! Just get units text here.
    ! Init_WetDep gets the unit conversion factors from Group_Scale.
    unitscale = Units_Scale(WDEP_WANTED(ind)%txt3, -1, unittxt)
    call AddNewDeriv( dname,  "WDEP ","-","-", unittxt ,  &
            igrp, -99,   F,      1.0,   F,    IOU_DAY)
  case default
    call CheckStop("Unknown WDEP_WANTED type " // trim(WDEP_WANTED(ind)%txt2) )
  endselect
  if(MasterProc) write(*,*)"Wet deposition output: ",trim(dname)," ",trim(unittxt)
enddo

!Emissions:
! We use mg/m2 outputs for consistency with depositions
! Would need to multiply by GridArea_m2 later to get ktonne/grid, but not
! done here.
!
! BVOC called every dt_advec, so use dt_scale=1.0e6 to get from kg/m2/s to
!  mg/m2 accumulated (after multiplication by dt_advec)

    ! AddNewDeriv( name,class,subclass,txt,unit,
    !    index,f2d, dt_scale,scale, avg,iotype,Is3D)

  do  ind = 1, NEMIS_BioNat
     dname = "Emis_mgm2_BioNat" // trim(EMIS_BioNat(ind) )
     call AddNewDeriv( dname, "NatEmis", "-", "-", "mg/m2", &
                 ind , -99, T ,    1.0e6,     F, IOU_DAY )
   end do

! SNAP emissions called every hour, given in kg/m2/s, but added to
! d_2d every advection step, so get kg/m2.
! Need 1.0e6 to get from kg/m2 to mg/m2 accumulated.
!
! Future option - might make use of Emis_Molwt to get mg(N)/m2
do  ind = 1, size(EMIS_FILE)
  dname = "Emis_mgm2_" // trim(EMIS_FILE(ind))
  call AddNewDeriv( dname, "SnapEmis", "-", "-", "mg/m2", &
                     ind , -99, T,  1.0e6,  F,  IOU_DAY )
end do ! ind


call AddNewDeriv("SURF_PM25water", "PM25water", "-", "-", "-", &
                      -99 , -99, F, 1.0,   T,  IOU_DAY )
!call AddNewDeriv("SURF_PM25", "PM25", "-", "-", "-", &
!                      -99 , -99, F, 1.0,   T,  IOU_DAY )

call AddNewDeriv("AOD", "AOD", "-", "-", "-", &
                      -99 , -99, F, 1.0,   T, IOU_DAY )


! As for GRIDAOT, we can use index for the threshold
call AddNewDeriv( "SOMO35","SOMO",  "SURF","-",   "ppb.day", &
                  35, -99, F, 1.0,   F,   IOU_MON )
call AddNewDeriv( "SOMO0 ","SOMO",  "SURF","-",   "ppb.day", &
                  0 , -99, F, 1.0,   F,   IOU_MON )
if(iadv_o3>0) &
call AddNewDeriv( "SURF_MAXO3","MAXADV", "O3","-",   "ppb", &
           iadv_o3, -99, F, PPBINV,   F,   IOU_DAY)

!-- 3-D fields

Is3D = .true.


do ind = 1, size(D3_OTHER)
  select case ( trim(D3_OTHER(ind)) )

  case ("D3_PM25water")

    call AddNewDeriv("D3_PM25water", "PM25water3d", "-", "-", "-", &
         -99, -99, F, 1.0,   T,  IOU_MON,    Is3D ) !

  case ("D3_m_TH")

    call AddNewDeriv("D3_m_TH","TH", "-","-",   "m", &
         -99, -99, F,  1.0,  F,  IOU_MON,     Is3D )

  case ("D3_m2s_Kz")

    call AddNewDeriv( "D3_Kz","Kz", "-","-",   "-", &
         -99, -99, F,  1.0,  F,  IOU_MON,     Is3D )

  case ("D3_T")

    call AddNewDeriv("D3_T","T", "-","-",   "K", &
         -99, -99, F,  1.0,  T,  IOU_MON,     Is3D )

  end select
end do

  ! Get indices of wanted fields in larger def_xx arrays:
  do i = 1, num_deriv2d
    ind = find_index( wanted_deriv2d(i), def_2d(:)%name )
    if (ind>0) then
      f_2d(i) = def_2d(ind)
      if ( found_ind2d(ind) > 0 ) then
          print *, "D2IND", me, trim( wanted_deriv2d(i) )
          do n = 1, size(def_2d(:)%name)
             print *, "D2IND def2d", n, trim( def_2d(n)%name )
          end do

      call CheckStop ( found_ind2d(ind) > 0,  &
        "REQUESTED 2D DERIVED ALREADY DEFINED: " // trim( def_2d(ind)%name) )
       end if
      found_ind2d(ind)  = 1
    else
      print *,"OOOPS wanted_deriv2d not found: ", wanted_deriv2d(i)
      print *,"OOOPS N,N :", num_deriv2d, Nadded2d
      if (MasterProc) then
        print "(a,i4,a)",("Had def_2d: ",idebug,&
          trim(def_2d(idebug)%name),idebug = 1, Nadded2d)
        call CheckStop("OOPS STOPPED" // trim( wanted_deriv2d(i) ) )
      endif
    endif
    if (DEBUG.and.MasterProc) print "(2(a,i4),3(1x,a))","Index f_2d ",i,  &
      " = def ",ind,trim(def_2d(ind)%name),trim(def_2d(ind)%unit),trim(def_2d(ind)%class)
  enddo

  do i = 1, num_deriv3d
    if (DEBUG.and.MasterProc) print *,"CHECK 3d", &
      num_deriv3d, i, trim(wanted_deriv3d(i))
    ind = find_index( wanted_deriv3d(i), def_3d(:)%name )
    call CheckStop ( found_ind3d(ind) > 0,  &
      "REQUESTED 3D DERIVED ALREADY DEFINED: "// trim(def_3d(ind)%name)  )
    found_ind3d(ind)  = 1
    f_3d(i) = def_3d(ind)
    if (DEBUG.and.MasterProc) print "(2(a,i4),3(1x,a))","Index f_3d ",i,  &
      " = def ",ind,trim(def_3d(ind)%name),trim(def_3d(ind)%unit),trim(def_3d(ind)%class)
  enddo


  !Initialise to zero
  if (num_deriv2d > 0) d_2d(:,:,:,:) = 0.0
  if (num_deriv3d > 0) d_3d(:,:,:,:,:) = 0.0

  debug_flag = ( DEBUG  .and. debug_proc )

  ! Determine actual output time ranges for Wanted output
  iou_min=+999
  iou_max=-999
  if(num_deriv2d>0)then
    iou_min=min(iou_min,minval(f_2d%iotype))
    iou_max=max(iou_max,maxval(f_2d%iotype))
  endif
  if(num_deriv3d>0)then
    iou_min=min(iou_min,minval(f_3d%iotype))
    iou_max=max(iou_max,maxval(f_3d%iotype))
  endif

  if (SOURCE_RECEPTOR.and..not.FORECAST)&  ! We assume that no daily & hourly outputs
    iou_max=IOU_MON                        ! are wanted on SOURCE_RECEPTOR mode

  if (SOURCE_RECEPTOR) &                   ! We need yearly for SR always
    iou_min=IOU_YEAR                       !

  if (FORECAST) &                          ! Only dayly & hourly outputs
    iou_min=IOU_DAY                        ! are wanted on FORECAST mode

  if (MasterProc) print "(a,2i4)","IOU_MAX ",  iou_max, iou_min

  end subroutine Define_Derived
 !=========================================================================
  subroutine Setups()
     integer :: n

    !/** flexibility note. By making use of character-based tests such
    !    as for "VOC" below, we achieve code which can stay for
    !    different chemical mechanisms, without having to define non-used indices.

    !/ ** if voc wanted, set up voc_array. Works for all ozone chemistries

      if ( any(  f_2d(:)%class == "VOC" ) ) then !TMP .or. &
          !TMP           any(  f_3d(:)%class == "VOC" )  ) then
          ! was call Setup_VOC(), moved here Mar 2010
          !--------------------------------------------------------
          ! Searches through the advected species and colects the
          ! index and carbon content of nmhc/voc species, as they are
          ! defined in CM_ChemSpecs_ml
          !
          !--------------------------------------------------------

         !====================================================================
          do n = 1, NSPEC_ADV

            if ( species( NSPEC_SHL+n )%carbons > 0 .and. &
                 species( NSPEC_SHL+n )%name   /= "CO"  .and. &
                 species( NSPEC_SHL+n )%name   /= "CH4" ) then

                 nvoc = nvoc + 1
                 voc_index(nvoc) = n
                 voc_carbon(nvoc) = species( NSPEC_SHL+n )%carbons
            end if
          end do
         !====================================================================
          !if (DEBUG  .and. MasterProc )then
          if ( MasterProc )then
               write(6,*) "Derived VOC setup returns ", nvoc, "vocs"
               write(6,"(a12,/,(20i3))")  "indices ", voc_index(1:nvoc)
               write(6,"(a12,/,(20i3))")  "carbons ", voc_carbon(1:nvoc)
          endif
      end if


    end subroutine Setups
    !=========================================================================

    subroutine Derived(dt,End_of_Day)

    !/** DESCRIPTION
    !  Integration and averaging of chemical fields. Intended to be
    !  a more flexible version of the old chemint routine.
    !  Includes AOT40, AOT60 if present

      real, intent(in)    :: dt           !  time-step used in intergrations
      logical, intent(in) :: End_of_Day   !  e.g. 6am for EMEP sites

      character(len=len(f_2d%class)) :: typ  !  See defs of f_2d
      character(len=TXTLEN_SHORT)    :: txt2
      real :: thour                          ! Time of day (GMT)
      real :: timefrac                       ! dt as fraction of hour (3600/dt)
      real :: dayfrac              ! fraction of day elapsed (in middle of dt)
      real :: af
      real, save :: km2_grid
      integer :: ntime                       ! 1...NTDAYS
      integer :: klow                        !  lowest extent of column data
      real, dimension(MAXLIMAX,MAXLJMAX) :: density !  roa (kgair m-3 when
                                                    ! scale in ug,  else 1
      real, dimension(MAXLIMAX,MAXLJMAX) :: tmpwork

      real, dimension(MAXLIMAX,MAXLJMAX,KMAX_MID) :: inv_air_density3D
                ! Inverse of No. air mols/cm3 = 1/M
                ! where M =  roa (kgair m-3) * MFAC  when ! scale in ug,  else 1
      logical, save :: first_call = .true.
      integer :: ipm25, ipmc ! will save some calcs for pm10
      integer :: igrp, ngrp  ! group methods
      integer, save :: ind_pmfine = -999, ind_pmwater = -999, & !needed for PM25
                       ind_pm10 = -999

      timefrac = dt/3600.0
      thour = current_date%hour+current_date%seconds/3600.0

      daynumber=day_of_year(current_date%year,current_date%month,&
                             current_date%day)


     ! Just calculate once, and use where needed

      forall ( i=1:limax, j=1:ljmax )
           density(i,j) = roa(i,j,KMAX_MID,1)
      end forall

     !/***** 2-D fields **************************

     ipm25 = 0  ! Reset once pm25 calculated
     ipmc  = 0  ! pm-coarse
     do n = 1, num_deriv2d

        typ = f_2d(n)%class

        if( debug_flag .and. first_call ) &
           write(*,"(a,i3,7a)") "Derive2d-typ",&
            n, "T:", trim(typ), "N:", trim(f_2d(n)%name), "C:",&
              trim(f_2d(n)%class), "END"



        !/** user-defined time-averaging. Here we have defined TADV and TVOC
        !    so that 8-hour daytime averages will be calculated.
        !    Just comment out if not wanted, or (better!) don't define any
        !    f_2d as TADV or TVOC

        if ( typ == "TADV" .or. typ == "TVOC" ) then
             if(thour <= 8.0 .or. thour > 16.0 ) cycle  ! Start next species
        end if

       ! hmix average at 00 and 12:

        if ( typ == "HMIX00" .or. typ == "XKSIG00" ) then
             if(thour /= 0.0 ) cycle  ! Start next species
        end if

        if ( typ == "HMIX12" .or. typ == "XKSIG12" ) then
             if(thour /= 12.0 ) cycle  ! Start next species
        end if

        index = f_2d(n)%index
        !if ( DEBUG .and. MasterProc .and. first_call ) then
        if (  MasterProc .and. first_call ) then
           write(*,"(a,i4,a,i4,a)") "1st call Derived 2d", n, &
              trim(f_2d(n)%name), index, trim(typ)
        end if

        select case ( typ )
          case ( "USTAR_NWP" )
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = ustar_nwp(i,j)
          end forall
         case ( "Kz_m2s" )
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = Kz_m2s(i,j,KMAX_BND-1)
            end forall
          case ( "ws_10m" )
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = ws_10m(i,j,1)
          end forall
          case ( "rh2m" )
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = rh2m(i,j,1)
          end forall
          case ( "u_ref" )
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = u_ref(i,j)
          end forall

          !case ( "SoilWater_deep" )
          case ( "SMI_deep" )
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = SoilWater_deep(i,j,1)
          end forall
          if ( debug_flag ) call write_debug(n,index, "SoilWater_DEEP")
          !if(debug_flag) print *, "SOILW_DEEP ", n, SoilWater_deep(2,2,1)

          !case ( "SoilWater_uppr" ) ! Not used so far. (=shallow)
          case ( "SMI_uppr" )
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = SoilWater_uppr(i,j,1)
          end forall
          if ( debug_flag ) call write_debug(n,index, "SoilWater_uppr")
          !if(debug_flag) print *, "SOILW_UPPR ",  n,  SoilWater_uppr(2,2,1)

          case ( "T2m" )
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = t2_nwp(i,j,1) - 273.15
          end forall
          case ( "Idirect" )
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = Idirect(i,j)
          end forall
          case ( "Idiffuse" )
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = Idiffuse(i,j)
          end forall

          case ( "SNOW" )
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = Grid_snow(i,j)
            end forall

          case ( "SNratio" )
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = min(3.0,so2nh3_24hr(i,j))
            end forall

          case ( "PSURF" )

            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = ps(i,j,1)*0.01
              !NOT YET - keep hPa in sites:d_2d( n, i,j,IOU_INST) = ps(i,j,1)
            end forall

          case ( "HMIX", "HMIX00", "HMIX12" )

            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = pzpbl(i,j)
            end forall

            if ( debug_flag ) then
             write(*,fmt="(a12,i4,f12.3)") "HMIX" , n , &
                     d_2d(n,debug_li,debug_lj,IOU_INST)
            end if

          case ( "SURF_PPB_SPEC" )
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = xn_adv(index,i,j,KMAX_MID) &
                                     * cfac(index,i,j)
            end forall
            if ( debug_flag ) call write_debugadv(n,index, 1.0, "PPB OUTS")

          case ( "SURF_MASS_SPEC" )  ! Here we need density

            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = xn_adv(index,i,j,KMAX_MID) &
                                     * cfac(index,i,j) * density(i,j)
            end forall
            if ( debug_flag ) call write_debugadv(n,index, &
                                     density(debug_li,debug_lj), "SURF_MASS")

          case ( "PM25water" )      !water

            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = PM25_water_rh50(i,j)
            end forall
            ind_pmwater = n

          case ( "PM25" )      ! Need to add PMFINE + fraction NO3_c
            if(first_call)then
              call CheckStop(f_2d(n)%unit/="ug","Wrong unit for "//trim(typ))
              call CheckStop(iadv_NO3_C<1,"Unknown specie NO3_C")
            endif

            !scale = 62.0
            ! All this size class has the same cfac.
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = d_2d(ind_pmfine,i,j,IOU_INST) + &
                                       fracPM25 * &
                  ( xn_adv(iadv_NO3_C,i,j,KMAX_MID) * ug_NO3_C &
                  ) * cfac(iadv_NO3_C,i,j) * density(i,j)
            end forall

          case ( "PM25_rh50" )      ! Need to add PMFINE + fraction NO3_c
            if(first_call)then
              call CheckStop(f_2d(n)%unit/="ug","Wrong unit for "//trim(typ))
              call CheckStop(iadv_NO3_C<1,"Unknown specie NO3_C")
            endif

            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = d_2d(ind_pmfine ,i,j,IOU_INST) &
!                                    + PM25_water_rh50(i,j)*ATWAIR/PPBINV  &
                                     + d_2d(ind_pmwater,i,j,IOU_INST) &
                                     + fracPM25 * &
                  ( xn_adv(iadv_NO3_C,i,j,KMAX_MID) * ug_NO3_C &
                  ) * cfac(iadv_NO3_C,i,j) * density(i,j)
            end forall

          case ( "PM25X" )      ! Need to add PMFINE + fraction NO3_c
            if(first_call)then
              call CheckStop(f_2d(n)%unit/="ug","Wrong unit for "//trim(typ))
            endif
            if (iadv_NO3_C      < 1 .or. & 
                iadv_EC_C_WOOD  < 1 .or. & 
                iadv_EC_C_FFUEL < 1 .or. & 
                iadv_POM_C_FFUEL< 1 ) then
                if ( first_call ) write(*,*) &
                     "WARNING: Derived - not all PM25X species present. Skipping"
                cycle   !! Skip this case
            end if

            !scale = 62.0
            ! All this size class has the same cfac.
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = d_2d(ind_pmfine,i,j,IOU_INST) + &
                                       fracPM25 * &
                  ( xn_adv(iadv_NO3_C      ,i,j,KMAX_MID) * ug_NO3_C       &
                  + xn_adv(iadv_EC_C_WOOD  ,i,j,KMAX_MID) * ug_EC_C_WOOD   &
                  + xn_adv(iadv_EC_C_FFUEL ,i,j,KMAX_MID) * ug_EC_C_FFUEL  &
                  + xn_adv(iadv_POM_C_FFUEL,i,j,KMAX_MID) * ug_POM_C_FFUEL &
                  ) * cfac(iadv_NO3_C,i,j) * density(i,j)
            end forall

         case ( "PM25X_rh50" )      ! Need to add PMFINE + fraction NO3_c + water
            if(first_call)then
              call CheckStop(f_2d(n)%unit/="ug","Wrong unit for "//trim(typ))
            endif
            if (iadv_NO3_C      < 1 .or. & 
                iadv_EC_C_WOOD  < 1 .or. & 
                iadv_EC_C_FFUEL < 1 .or. & 
                iadv_POM_C_FFUEL< 1 ) then
                if ( first_call ) write(*,*) &
                     "WARNING: Derived - not all PM25X_rh50 species present. Skipping"
                cycle   !! Skip this case
            end if

            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = d_2d(ind_pmfine ,i,j,IOU_INST) &
!                                    + PM25_water_rh50(i,j)*ATWAIR/PPBINV &
                                     + d_2d(ind_pmwater,i,j,IOU_INST) &
                                     + fracPM25 * &
                  ( xn_adv(iadv_NO3_C      ,i,j,KMAX_MID) * ug_NO3_C       &
                  + xn_adv(iadv_EC_C_WOOD  ,i,j,KMAX_MID) * ug_EC_C_WOOD   &
                  + xn_adv(iadv_EC_C_FFUEL ,i,j,KMAX_MID) * ug_EC_C_FFUEL  &
                  + xn_adv(iadv_POM_C_FFUEL,i,j,KMAX_MID) * ug_POM_C_FFUEL &
                  ) * cfac(iadv_NO3_C,i,j) * density(i,j)
            end forall

          case ( "PM10_rh50" )      ! Need to add PMFINE + fraction NO3_c
            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = d_2d(ind_pm10   ,i,j,IOU_INST) &
!                                    + PM25_water_rh50(i,j)*ATWAIR/PPBINV &
                                     + d_2d(ind_pmwater,i,j,IOU_INST)
            end forall

            if(DEBUG.and. debug_proc )  then
              if(first_call)then
                call CheckStop(f_2d(n)%unit/="ug","Wrong unit for "//trim(typ))
                call CheckStop(iadv_NO3_C      <1,"Unknown specie NO3_C")
                call CheckStop(iadv_EC_C_WOOD  <1,"Unknown specie EC_C_WOOD")
                call CheckStop(iadv_EC_C_FFUEL <1,"Unknown specie EC_C_FFUEL")
                call CheckStop(iadv_POM_C_FFUEL<1,"Unknown specie POM_C_FFUEL")
              endif
              write(*,*) "FRACTION PM25", n, ind_pmfine, ind_pmwater
              i= debug_li; j=debug_lj
              write(*,"(a,2i4,4es12.3)") "Adding PM25FRACTIONS:", n, ind_pmfine,  &
!                 PM25_water_rh50(i,j)* ATWAIR/PPBINV, &
                  d_2d(ind_pmwater,i,j,IOU_INST), &
                  d_2d(ind_pmfine ,i,j,IOU_INST), d_2d( n, i,j,IOU_INST), &
                  ug_NO3_C * xn_adv(iadv_NO3_C,i,j,KMAX_MID) &
                           * cfac(iadv_NO3_C,i,j) * density(i,j)
              write(*,"(a,i4,f5.2,4es12.3)") "CFAC PM25FRACTIONS:", n, fracPM25,  &
                      cfac(iadv_NO3_C    ,i,j), cfac(iadv_POM_C_FFUEL,i,j), &
                      cfac(iadv_EC_C_WOOD,i,j), cfac(iadv_EC_C_FFUEL ,i,j)
            endif

          case ( "AOD" )        !/ Aerosol Optical Depth

            forall ( i=1:limax, j=1:ljmax )
              d_2d( n, i,j,IOU_INST) = AOD(i,j)
            end forall

          case ( "MAXADV" )

            if (  f_2d(n)%unit == "ppb"  ) then

               d_2d( n, 1:limax,1:ljmax,IOU_DAY) = &
                 max( d_2d( n, 1:limax,1:ljmax,IOU_DAY),  &
                      xn_adv(index,1:limax,1:ljmax,KMAX_MID)  &
                     * cfac(index,1:limax,1:ljmax) )
               txt2 = "MAXADV ppb for " // trim( f_2d(n)%name)
             else
               d_2d( n, 1:limax,1:ljmax,IOU_DAY) = &
                 max( d_2d( n, 1:limax,1:ljmax,IOU_DAY),  &
                      xn_adv(index,1:limax,1:ljmax,KMAX_MID)  &
                     * cfac(index,1:limax,1:ljmax) * density(1:limax,1:ljmax) )
               txt2 = "MAXADV ug for " // trim( f_2d(n)%name)
             end if

            if ( debug_flag ) call write_debugadv(n,index, &
                                     density(debug_li,debug_lj), txt2 )

            !Monthly and yearly ARE averaged over days
            if(End_of_Day)then
              d_2d(n,:,:,IOU_MON )  = d_2d(n,:,:,IOU_MON )  + d_2d(n,:,:,IOU_DAY)
              nav_2d(n,IOU_MON) = nav_2d(n,IOU_MON) + 1
              if(    current_date%month >= 4 &
                 .or.current_date%month <= 9 )then
              d_2d(n,:,:,IOU_YEAR ) = d_2d(n,:,:,IOU_YEAR ) + d_2d(n,:,:,IOU_DAY)
              nav_2d(n,IOU_YEAR) = nav_2d(n,IOU_YEAR) + 1
              endif
            endif


          case ( "MAXSHL" )        ! Daily maxima - short-lived

            if (  f_2d(n)%unit /= "ppb"  ) then  ! Mix ratio so far
               forall ( i=1:limax, j=1:ljmax )
                 d_2d( n, i,j,IOU_DAY) = max( d_2d( n, i,j,IOU_DAY), &
                     xn_shl(index,i,j,KMAX_MID) )
               end forall
            else
               forall ( i=1:limax, j=1:ljmax )
                 d_2d( n, i,j,IOU_DAY) = max( d_2d( n, i,j,IOU_DAY), &
                     xn_shl(index,i,j,KMAX_MID)  / (density(i,j)*MFAC) )
               end forall
            end if


            if ( debug_flag ) then
               write(*, *) "SHL:MAX.,MFAC ", n, index  , MFAC
               write(*,fmt="(a12,2i4,4es12.3)") "SHL MAX. ", n, index  &
                      , d_2d(n,debug_li,debug_lj,IOU_DAY) &
                      ,  xn_shl(index,debug_li,debug_lj,KMAX_MID)  &
                      ,  density(debug_li,debug_lj), MFAC
            end if

            !Monthly and yearly ARE averaged over days
            if(End_of_Day)then
              d_2d(n,:,:,IOU_MON ) = d_2d(n,:,:,IOU_MON ) + d_2d(n,:,:,IOU_DAY)
              nav_2d(n,IOU_MON) = nav_2d(n,IOU_MON) + 1
              if(    current_date%month >= 4 &
                 .or.current_date%month <= 9 )then
              d_2d(n,:,:,IOU_YEAR ) = d_2d(n,:,:,IOU_YEAR ) + d_2d(n,:,:,IOU_DAY)
              nav_2d(n,IOU_YEAR) = nav_2d(n,IOU_YEAR) + 1
              endif
            endif

          case ( "VOC", "TVOC" )

            call voc_2dcalc()

          case( "GRIDAOT" )!  Hardly used these days. The vegetation-specific
                           !  AOTs are handled in the Mosaic class and as
                           !  part of the dry dep calculations.
            if(first_call)&
              call CheckStop(iadv_o3<1,"Unknown specie O3")

            d_2d(n, 1:limax, 1:ljmax, IOU_INST) = &
                 Calc_GridAOTx( f_2d(n)%index, debug_proc,"DERIVAOT")

           if( DEBUG_AOT .and. debug_proc ) then
             call datewrite("AOTDEBUG" // trim(f_2d(n)%name), n, &
               (/ zen(debug_li,debug_lj), real(f_2d(n)%index), &
                  xn_adv(iadv_O3,debug_li,debug_lj,KMAX_MID)*&
                     cfac(iadv_O3,debug_li,debug_lj)*PPBINV, &
                  d_2d(n, debug_li, debug_lj, IOU_INST )  /) )
           end if

           case( "SOMO" )
            if(first_call)&
              call CheckStop(iadv_o3<1,"Unknown specie O3")

              !dt/7200: half a dt time step in hours
              !dayfrac "points" to the middle of the integration step
              dayfrac= (thour-(dt/7200.))/24. !must be < 1
              ntime=int(dayfrac*NTDAY )+1 !must be >=1 and <= NTDAY
              if(dayfrac<0)ntime=NTDAY !midnight

        !last value  (not averaged):
          D2_O3_DAY( : , : , ntime) =&
           xn_adv(iadv_o3,:,:,KMAX_MID)*cfac(iadv_o3,:,:)*PPBINV

              if(dayfrac<0)then !only at midnight: write on d_2d


                 call somo_calc( n, f_2d(n)%index, DEBUG .and. debug_proc )
                 d_2d(n,:,:,IOU_MON )  = d_2d(n,:,:,IOU_MON )  + d_2d(n,:,:,IOU_DAY)

                ! if(current_date%month>=4.and.current_date%month<=9)then
                 d_2d(n,:,:,IOU_YEAR ) = d_2d(n,:,:,IOU_YEAR ) + d_2d(n,:,:,IOU_DAY)
                !NB overwritten anyway D2_O3_DAY = 0.
              endif


          case ( "PREC", "WDEP", "DDEP", "VG" ,"Rs", "Rns", "Gns", "Mosaic", "POD", "SPOD", "AOT" )
!            if ( debug_flag ) write(*,"(2a,i4,a,es12.3)")"PROCESS ",trim(typ),&
!                   n, trim(f_2d(n)%name), d_2d(n,debug_li,debug_lj,IOU_INST)
!            Nothing to do - all set in My_DryDep

          case ( "COLUMN" ) ! MFAC gives #/cm3, 100 is for m -> cm

            read(unit=f_2d(n)%subclass,fmt="(a1,i2)") txt2, klow ! Connvert e.g. k20 to klow=20
            !klow = f_2d(n)%LC  ! here we have used LC to set vertical limit

            do j = 1, ljmax
            do i = 1, limax
               k = 1
               tmpwork( i,j ) =  &
                    xn_adv(index,i,j,k)  * &
                    roa(i,j,k,1)* (z_bnd(i,j,k)-z_bnd(i,j,k+1))

               do k = 2, klow   !!! KMAX_MID
                  tmpwork( i,j ) = tmpwork( i,j ) + &
                    xn_adv(index,i,j,k)  * &
                    roa(i,j,k,1) * (z_bnd(i,j,k)-z_bnd(i,j,k+1))
                  if( DEBUG_COLUMN .and. debug_flag .and. &
                         i == debug_li .and. j == debug_lj ) then
                     write(*,"(a,3i4,a4,f8.3,f8.1,2es12.3)") &
                        trim(f_2d(n)%name), n, index, k, " => ", &
                        roa(i,j,k,1), z_bnd(i,j,k)-z_bnd(i,j,k+1), &
                        xn_adv(index,i,j,k),tmpwork(i,j)
                  end if
               end do ! k
               d_2d( n, i, j, IOU_INST) = MFAC * 100.0 * tmpwork( i, j ) ! Should be molec/cm2


            end do !i
            end do !j
            if( debug_flag ) &
                write(*,"(a18,es12.3)") "COLUMN d2_2d", &
                     d_2d( n, debug_li, debug_lj, IOU_INST)


         case ( "EcoFrac" ) ! ODD TO HAVE FRAC AND AREA BELOW:"ECOAREA" )

            if( .not. first_call ) cycle ! Only need to do once
            if( f_2d(n)%Index == FULL_ECOGRID ) then
              km2_grid = (GRIDWIDTH_M*GRIDWIDTH_M) * 1.0e-6 ! km2
              forall ( i=1:limax, j=1:ljmax )
                  d_2d(n,i,j,IOU_YEAR) =  EcoSystemFrac( f_2d(n)%Index ,i,j)&
                        * KM2_GRID /xm2(i,j)
              end forall
            else
              forall ( i=1:limax, j=1:ljmax )
                  d_2d(n,i,j,IOU_YEAR) =  EcoSystemFrac( f_2d(n)%Index ,i,j)
              end forall
            end if
            if( debug_flag ) &
                write(*,"(a18,a,i4,a,2es12.3)") "ECOD2D ", &
                 " f2d:", f_2d(n)%Index, &
                 " Frac", EcoSystemFrac( f_2d(n)%Index, debug_li,debug_lj), &
                 !!" Index: ", DepEcoSystem(n)%Index, &
                    d_2d( n, debug_li, debug_lj, IOU_YEAR)

          case ( "NatEmis" ) !emissions in kg/m2/s converted??

              forall ( i=1:limax, j=1:ljmax )
                  d_2d(n,i,j,IOU_INST) =  EmisNat( f_2d(n)%Index,i,j )
              end forall
              !Not done, keep mg/m2  * GridArea_m2(i,j)
              if ( debug_flag ) call write_debug(n,f_2d(n)%Index, "NatEmis")
            if( debug_flag ) &
              call datewrite("NatEmis-in-Derived, still kg/m2/s", &
                f_2d(n)%Index, (/ EmisNat( f_2d(n)%Index, debug_li,debug_lj) /) )

          case ( "SnapEmis" ) !emissions in kg/m2/s converted??

              forall ( i=1:limax, j=1:ljmax )
                  d_2d(n,i,j,IOU_INST) =  SumSnapEmis( i,j, f_2d(n)%Index)
              end forall
              !not done, to keep mg/m2 * GridArea_m2(i,j)
            if( debug_flag .and. f_2d(n)%Index == 3  ) & ! CO:
              call datewrite("SnapEmis-in-Derived, still kg/m2/s", n, & !f_2d(n)%Index,&
                    (/   SumSnapEmis( debug_li,debug_lj, f_2d(n)%Index ) /) )


          case ( "EXT" )

          ! Externally set for IOU_INST (in other routines); so no new work
          ! needed except decision to accumalate to yearly or not.

            if ( debug_flag ) write(*,"(a18,i4,a12,a4,es12.3)")"EXT d_2d",&
                   n, f_2d(n)%name, " is ", d_2d(n,debug_li,debug_lj,IOU_INST)


          case ( "SURF_MASS_GROUP" ) !
            igrp = f_2d(n)%index
            call CheckStop(igrp<1, "NEG GRP "//trim(f_2d(n)%name) )
            call CheckStop(igrp>size( GROUP_ARRAY(:)%name ), &
                 "Outside GRP "//trim(f_2d(n)%name) )
            ngrp = GROUP_ARRAY(igrp)%Ngroup

            if( GROUP_ARRAY(igrp)%name == "PMFINE" .and. ind_pmfine<0 ) then
               ind_pmfine = n
               if( MasterProc) write(*,"(a,2i4,2a15)") "FOUND FINE FRACTION ",&
                   n, ind_pmfine, &
                     trim(GROUP_ARRAY(igrp)%name), trim(f_2d(n)%name)
            end if
            if( GROUP_ARRAY(igrp)%name == "PM10" .and. ind_pm10<0 ) then
               ind_pm10 = n
               if( MasterProc) write(*,"(a,2i4,2a15)") "FOUND PM10 FRACTION ",&
                   n, ind_pm10, &
                     trim(GROUP_ARRAY(igrp)%name), trim(f_2d(n)%name)
            end if
            if(DEBUG.and. MasterProc ) then
                write(*,*) "CASEGRP ", n, igrp, ngrp, trim(typ)
                write(*,*) "CASENAM ", trim(f_2d(n)%name)
                write(*,*) "CASEGRP:", GROUP_ARRAY(igrp)%itot(1:ngrp)
                write(*,*) "CASEunit", trim(f_2d(n)%unit)
            end if
            call uggroup_calc(d_2d(n,:,:,IOU_INST), density, &
                              f_2d(n)%unit, 0, igrp)

            if(DEBUG.and. debug_proc .and. n==ind_pmfine )  then
                i= debug_li; j=debug_lj
                write(*,"(a,2i4,3es12.3)") "PMFINE FRACTION:", n, ind_pmfine,  &
                   d_2d(ind_pmfine,i,j,IOU_INST)
            end if
            if(DEBUG.and. debug_proc .and. n==ind_pm10 )  then
                i= debug_li; j=debug_lj
                write(*,"(a,2i4,3es12.3)") "PM10 FRACTION:", n, ind_pm10,  &
                   d_2d(ind_pm10,i,j,IOU_INST)
            end if

          case  default

            if ( debug_flag ) then
               if( debug_flag .and. i == debug_li .and. j == debug_lj ) &
                 write(*,"(a,i3,4a)") "My_Deriv Defaults called n=",&
                    n, " Type ",trim(typ), " Name ", trim( f_2d(n)%name )

                 write(*,"(a,i3,i8,i4,a)") &
                    "My_Deriv index?, nav? length?, class? ", index,&
                    nav_2d(n,IOU_INST), len(f_2d%class), trim(f_2d(n)%class)
                 write(*,*) "My_Deriv index?, avg ", f_2d(n)%avg
             end if

             call My_DerivFunc( d_2d(n,:,:,IOU_INST), typ ) ! , density )

        end select


        !/** add to daily, monthly and yearly average, and increment counters
        !  Note that the MAXADV and MAXSHL and SOMO needn't be summed here, but
        !  since the INST values are zero it doesn't harm, and the code is
        !  shorter. These d_2d ( MAXADV, MAXSHL, SOMO) are set elsewhere

        af = 1.0 ! accumlation factor
        if( f_2d(n)%dt_scale ) then !need to scale with dt_advec
            af = dt_advec
        end if

!print *, "D2Ding", me, n, trim(f_2d(n)%name)
        d_2d(n,:,:,IOU_DAY )  = d_2d(n,:,:,IOU_DAY )  + af*d_2d(n,:,:,IOU_INST)
        if ( f_2d(n)%avg ) nav_2d(n,IOU_DAY) = nav_2d(n,IOU_DAY) + 1

        d_2d(n,:,:,IOU_MON )  = d_2d(n,:,:,IOU_MON )  + af*d_2d(n,:,:,IOU_INST)
        if ( f_2d(n)%avg ) nav_2d(n,IOU_MON) = nav_2d(n,IOU_MON) + 1

        d_2d(n,:,:,IOU_YEAR ) = &
                 d_2d(n,:,:,IOU_YEAR ) + af*d_2d(n,:,:,IOU_INST)
        if ( f_2d(n)%avg ) nav_2d(n,IOU_YEAR) = nav_2d(n,IOU_YEAR) + 1

        !if( debug_flag .and. n == 27  ) then ! C5H8 BvocEmis:
        !if(  n == 27  ) then ! C5H8 BvocEmis:
        !   print *, " TESTING NatEmis ", n, af, f_2d(n)%Index, f_2d(n)
        !      call datewrite("NatEmis-end-Derived", n, (/ af, &
        !         SumSnapEmis( debug_li,debug_lj, f_2d(n)%Index), &
        !         d_2d(n,debug_li,debug_lj,IOU_INST), &
        !         d_2d(n,debug_li,debug_lj,IOU_DAY), &
        !         d_2d(n,debug_li,debug_lj,IOU_MON), &
        !         d_2d(n,debug_li,debug_lj,IOU_YEAR) &
        !       /) )
        !end if

     end do   ! num_deriv2d

     !/***** 3-D fields **************************

       if(debug_flag) then ! RUN through indices etc.
            write(*, "(a12,2i4,f12.3)") "3D3D TIME ",  me, num_deriv3d, &
                     (current_date%hour+current_date%seconds/3600.0)
        end if


     do n = 1, num_deriv3d

        index = f_3d(n)%index

       if (  f_3d(n)%unit == "ppb"  ) then
            inv_air_density3D(:,:,:) = 1.0
       else  !OLD if ( f_3d(n)%rho ) then
            forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
                inv_air_density3D(i,j,k) = 1.0/( roa(i,j,k,1) * MFAC )
            end forall
        end if

        select case ( f_3d(n)%class )

         ! Simple advected species:
         case ( "ADV" )

            forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
              d_3d( n, i,j,k,IOU_INST) = xn_adv(index,i,j,k)
            end forall

         case ( "BGN" )

            forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
              d_3d( n, i,j,k,IOU_INST) = xn_bgn(index,i,j,k)
            end forall

         case ( "PM25water3d" )    !particle water

            forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
              d_3d( n, i,j,k,IOU_INST) = PM25_water(i,j,k)
            end forall

         case ("XKSIG00", "XKSIG12" ) !hf hmix Kz_m2s

            forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
              d_3d( n, i,j,k,IOU_INST) = Kz_m2s(i,j,k)
            end forall

         case ("TH  " ) !JEJ Pot. temp (needed for cross sections)

            forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
              d_3d( n, i,j,k,IOU_INST) = th(i,j,k,1)
            end forall

         case ("T   " ) ! Absolute Temperature

            forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
               d_3d( n, i,j,k,IOU_INST) = th(i,j,k,1)&
                   *exp(KAPPA*log((PT+sigma_mid(k)*(ps(i,j,1) - PT))*1.e-5))
                 !NB: PT and PS in Pa
            end forall

         case ( "MAX3DSHL" ) ! Daily maxima - short-lived

            if (  f_3d(n)%unit == "ppb"  ) then
              call CheckStop("Asked for MAX3DSHL ppb ")
            else
              forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
                d_3d( n, i,j,k,IOU_INST) = max( d_3d( n, i,j,k,IOU_INST),&
                                      xn_shl(index,i,j,k) &
                                     * inv_air_density3D(i,j,k) )
            end forall
            end if

            if(debug_flag) write(*,"(a13,i4,f8.3,3es12.3)") "3D3D MAX3DSHL", n, thour, &
              xn_shl(index,debug_li,debug_lj,KMAX_MID), &
              1.0/inv_air_density3D(debug_li,debug_lj,KMAX_MID), &
              d_3d(n,debug_li,debug_lj,KMAX_MID,IOU_INST)

          case ( "MAX3DADV" )
            forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
              d_3d( n, i,j,k,IOU_INST) =  max( d_3d( n, i,j,k,IOU_INST),&
                                               xn_adv(index,i,j,k) )
            end forall

             if(debug_flag) write(*,"(a12,i4,f8.3,4es12.3)") "SET MAX3DADV", n, thour, &
                      xn_adv(index,debug_li,debug_lj,KMAX_MID), &
                      d_3d(n,debug_li,debug_lj,KMAX_MID,IOU_INST)

          case ( "SHL" )
            forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
              d_3d( n, i,j,k,IOU_INST) =   xn_shl(index,i,j,k) * inv_air_density3D(i,j,k)
            end forall


          case ( "VOC" )

            call voc_3dcalc()

        case ( "3D_PPB_SPEC" )

            forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
              d_3d( n, i,j,k,IOU_INST) = xn_adv(index,i,j,k)
            end forall
           if ( debug_flag ) call write_debugadv(n,index, 1.0, "3D PPB OUTS")

        case ( "3D_MASS_SPEC" )

            forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
              d_3d( n, i,j,k,IOU_INST) = xn_adv(index,i,j,k) * roa(i,j,k,1)
            end forall
           if ( debug_flag ) call write_debugadv(n,index, 1.0, "3D UG OUTS")

        case ( "3D_MASS_GROUP" ) !
            igrp = f_3d(n)%index
            call CheckStop(igrp<1, "NEG GRP "//trim(f_3d(n)%name) )
            call CheckStop(igrp>size( GROUP_ARRAY(:)%name ), &
                 "Outside GRP "//trim(f_3d(n)%name) )
            ngrp = GROUP_ARRAY(igrp)%Ngroup
            if(DEBUG.and. MasterProc ) then
                write(*,*) "3DCASEGRP ", n, igrp, ngrp, trim(typ)
                write(*,*) "3DCASENAM ", trim(f_3d(n)%name)
                write(*,*) "3DCASEGRP:", GROUP_ARRAY(igrp)%itot(1:ngrp)
                write(*,*) "3DCASEunit", trim(f_3d(n)%unit)
            endif
            do k=1,KMAX_MID
              call uggroup_calc(d_3d(n,:,:,k,IOU_INST), roa(:,:,k,1), &
                                f_3d(n)%unit, k, igrp)
            enddo

         case ( "Kz" )

            forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
              d_3d( n, i,j,k,IOU_INST) = Kz_m2s(i,j,k)
            end forall


          case  default

           write(*,"(a,2i3,3a)") "*** NOT FOUND",n,index, trim(f_3d(n)%name),&
                 ";Class:", trim(f_3d(n)%class)
           write(unit=errmsg,fmt=*) "Derived 3D class NOT FOUND", n, index, &
                         trim(f_3d(n)%name),trim(f_3d(n)%class)
           call CheckStop( errmsg )


        end select


      !/** add to monthly and yearly average, and increment counters
       !    ( no daily averaging done for 3-D fields so far).


       ! For the MAX3D possibilities, we store maximum value of the
       !   current day in the IOU_INST variables.
       !   These are then added into IOU_MON **only** at the end of each day.
       ! (NB there is an error made on 1st day used, since only 1st 6 hours
       !  are checked. Still, not much happens on 1st Jan.... ;-)

        if ( (f_3d(n)%class == "MAX3DSHL")  .or. &
             (f_3d(n)%class == "MAX3DADV") )then
           if (End_of_Day) then
              d_3d(n,:,:,:,IOU_MON ) = d_3d(n,:,:,:,IOU_MON ) &
                                     + d_3d(n,:,:,:,IOU_INST)
              d_3d(n,:,:,:,IOU_YEAR) = d_3d(n,:,:,:,IOU_YEAR) &
                                     + d_3d(n,:,:,:,IOU_INST)
              if ( f_3d(n)%avg )  nav_3d(n,:) = nav_3d(n,:) + 1 !only collected for end_of_day

              if( debug_flag ) then
                    write(*,fmt="(a20,a9,i4,f8.3,2es12.3)") "END_OF_DAY MAX3D", &
                      f_3d(n)%class, n, thour,  &
                      d_3d(n,debug_li,debug_lj,KMAX_MID,IOU_MON ),&
                      d_3d(n,debug_li,debug_lj,KMAX_MID,IOU_INST )
                    write(*,"(a20,i4,2x,6i6)") "END_OF_DAY NAV ", &
                      n, (nav_3d(n,i), i=1,LENOUT3D)
              end if

              d_3d(n,:,:,:,IOU_INST ) = 0.0  !! Reset d_3d

           endif ! End_of_Day
        else
           d_3d(n,:,:,:,IOU_DAY ) = d_3d(n,:,:,:,IOU_DAY ) &
                + d_3d(n,:,:,:,IOU_INST)
           d_3d(n,:,:,:,IOU_MON ) = d_3d(n,:,:,:,IOU_MON ) &
                + d_3d(n,:,:,:,IOU_INST)
           d_3d(n,:,:,:,IOU_YEAR) = d_3d(n,:,:,:,IOU_YEAR) &
                + d_3d(n,:,:,:,IOU_INST)
           if ( f_3d(n)%avg )  nav_3d(n,:) = nav_3d(n,:) + 1
        endif


!      !/** add to monthly and yearly average, and increment counters
!      !    ( no daily averaging done for 3-D fields so far).
!
!       d_3d(n,:,:,:,IOU_MON ) = d_3d(n,:,:,:,IOU_MON ) &
!                              + d_3d(n,:,:,:,IOU_INST)
!       d_3d(n,:,:,:,IOU_YEAR) = d_3d(n,:,:,:,IOU_YEAR) &
!                              + d_3d(n,:,:,:,IOU_INST)
!
!       if ( f_3d(n)%avg )  nav_3d(n,:) = nav_3d(n,:) + 1

      end do

      first_call = .false.

    end subroutine Derived
    !=========================================================================

    subroutine DerivedProds(text,dt)

    !/** DESCRIPTION
    !  Calculates chemical changes by comparing values before and  after
    !  chemistry subroutine. Intended to be a more flexible version of the old
    !  PRODO3  calculation

      character(len=*), intent(in) :: text  ! "Before" or "After"
      real,             intent(in) :: dt    ! timestep (s)

      real :: timefrac                      ! dt as fraction of hour (3600/dt)



!      if ( num_deriv3d < 1 ) print *, "DerivedProds "//text, num_deriv3d
      if ( num_deriv3d < 1 ) return
      if (.not. any( f_3d%class == "PROD" ) ) return

      timefrac = dt/3600.0

     !/***** 3-D fields **************************

     do n = 1, num_deriv3d

        if ( f_3d(n)%class  == "PROD " ) then
           index = f_3d(n)%index

           select case ( text )

               case ( "Before" )   !! Initialise to xn_adv

                 forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
                   d_3d( n, i,j,k,IOU_INST) = xn_adv(index,i,j,k)
                 end forall

               case ( "After" )    !! Calculate change

                 forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
                   d_3d( n, i,j,k,IOU_INST) = &
                      d_3d( n, i,j,k,IOU_INST) - xn_adv(index,i,j,k)
                 end forall

           end select
        end if
      end do

    end subroutine DerivedProds
    !=========================================================================

    subroutine ResetDerived(period)
      integer, intent(in) :: period   ! Either IOU_DAY or IOU_MON

       if ( period <= LENOUT2D ) then
           nav_2d  (:,period) = 0
           d_2d(:,:,:,period) = 0.0
       end if


       if ( num_deriv3d > 0 .and.  period <= LENOUT3D ) then
           nav_3d    (:,period) = 0
           d_3d(:,:,:,:,period) = 0.0
       end if

    end subroutine ResetDerived
 !=========================================================================


   subroutine voc_2dcalc()

    !/-- Sums up voc species using the indices defined earlier in Setup_VOCs

     ! We initialise d_2d first, the use a simple loop
     ! over voc. Some CPU could be saved by initialising
     ! with the 1st voc, then looping over 2, nvoc, but who cares...


      d_2d( n, 1:limax,1:ljmax,IOU_INST) =  0.0

      do ivoc = 1, nvoc

         index = voc_index(ivoc)           ! Gives which IXADV_ to use.
         forall ( i=1:limax, j=1:ljmax )
             d_2d( n, i,j,IOU_INST) = d_2d( n, i,j,IOU_INST)      &
                                    + xn_adv(index,i,j,KMAX_MID)  &
                                    * voc_carbon(ivoc) * cfac(index,i,j)
                               ! multiplied by nr. of C and "reduced to surface"
         end forall
      end do ! ivoc
   end subroutine voc_2dcalc

 !=========================================================================
   subroutine voc_3dcalc()

    !/-- as for voc_2dcalc

      d_3d( n, 1:limax,1:ljmax,1:KMAX_MID,IOU_INST) =  0.0

      do ivoc = 1, nvoc

         index = voc_index(ivoc)
         forall ( i=1:limax, j=1:ljmax, k=1:KMAX_MID )
             d_3d( n, i,j,k,IOU_INST) = d_3d( n, i,j,k,IOU_INST) + &
                     xn_adv(index,i,j,k)*voc_carbon(ivoc)
         end forall
      end do ! ivoc

   end subroutine voc_3dcalc
 !=========================================================================
subroutine uggroup_calc( ug_2d, density, unit, ik, igrp)

  !/--  calulates e.g. SIA = SO4 + pNO3_f + pNO3_c + aNH4
  ! (only SIA converted to new group system so far, rv3_5_6 )
  !/--  calulates also PM10  = SIA + PPM2.5 + PPMCOARSE

  real, dimension(:,:), intent(out) :: ug_2d  ! i,j section of d_2d arrays
  real, intent(in), dimension(MAXLIMAX,MAXLJMAX)  :: density
  character(len=*), intent(in) :: unit
  integer, intent(in) :: ik,igrp

  integer, pointer, dimension(:) :: gspec=>null()       ! group array of indexes
  real,    pointer, dimension(:) :: gunit_conv=>null()  ! & unit conv. factors

  if(DEBUG.and.debug_proc) &
    write(*,"(a,L1,2i4)") "DEBUG GROUP-PM-N",debug_proc,me,ik
  call CheckStop(unit(1:2)/="ug","uggroup: Invalid deriv/level")
  call Group_Units(igrp,unit,gspec,gunit_conv,debug=DEBUG.and.debug_proc)

  if(ik==0)then
    forall(i=1:limax,j=1:ljmax) &
      ug_2d(i,j) = dot_product(xn_adv(gspec(:),i,j,KMAX_MID),&
                               cfac(gspec(:),i,j)*gunit_conv(:)) &
                 * density(i,j)
  else
    forall(i=1:limax,j=1:ljmax) &
      ug_2d(i,j) = dot_product(xn_adv(gspec(:),i,j,ik),gunit_conv(:)) &
                 * density(i,j)
  endif
  deallocate(gspec,gunit_conv)
end subroutine uggroup_calc
 !=========================================================================

  subroutine somo_calc( n, iX, debug_flag )


    !/-- Calculates SOMO (8hours) values for input threshold.

    implicit none
    integer, intent(in) :: n           ! index in Derived_ml::d_2d arrays
    integer, intent(in) :: iX          !  threshold, usually 35 ppb
    logical, intent(in) :: debug_flag

    real :: o3                         ! Ozone (ppb) - needed if SOMOs
    real :: sum8h
    integer, parameter :: N8h = (NTDAY*8)/24 !number of periods in 8 hours
    real, parameter :: N8h_inv=1./N8h
    integer :: nh


      do i=1,limax
        do j=1,ljmax

           !find max running 8h sum O3
           sum8h=0.
           do nh=1,N8h
              sum8h = sum8h + D2_O3_DAY( i , j , nh)
           enddo
           o3=sum8h
           do nh=N8h+1,NTDAY
              sum8h =sum8h-D2_O3_DAY( i , j , nh-N8h)+D2_O3_DAY( i , j , nh)
              o3=max(o3,sum8h)
              if(n<0)write(*,*)o3 !pw fake for compiler!!
           enddo

           !divide by N8h to find 8h mean
           o3=o3*N8h_inv

           if ( debug_flag .and. i==debug_li .and. j==debug_lj ) then
             write(*,"(a,2i4,f12.3)") "SOMO DEBUG ", n, iX, o3
           end if


           o3 = max( o3 - iX , 0.0 )   ! Definition of SOMOs

             ! d_2d values will be accumulated in Derived_ml

           d_2d(n, i,j,IOU_DAY ) = o3

        end do
      end do
   end subroutine somo_calc

 !=========================================================================
    subroutine write_debugadv(n,index,rho,txt)
       integer, intent(in) :: n, index
       real, intent(in) :: rho
       character(len=*) :: txt

       write(*,fmt="(2a,2i4,2a,4f12.3)") "PROCESS " , trim(txt) , n, index  &
                  ,trim(f_2d(n)%name)  &
                  ,trim(f_2d(n)%unit)  &
                  ,d_2d(n,debug_li,debug_lj,IOU_INST)*PPBINV &
                  ,xn_adv(index,debug_li,debug_lj,KMAX_MID)*PPBINV &
                  ,rho, cfac(index,debug_li,debug_lj)
    end subroutine write_debugadv
 !=========================================================================
    subroutine write_debug(n,index,txt)
       integer, intent(in) :: n, index
       character(len=*) :: txt

       write(*,fmt="(2a,2i4,a,4g12.3)") "DERIV: GEN " , txt , n, index  &
                  ,trim(f_2d(n)%name)  &
                  ,d_2d(n,debug_li,debug_lj,IOU_INST)
    end subroutine write_debug

 !=========================================================================
end module Derived_ml